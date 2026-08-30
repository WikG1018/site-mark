import CoreLocation
import Foundation
import Photos
import UIKit

/// Headless-safe implementation of the Pigeon `SiteMarkSystemApi`.
///
/// iOS port of AndroidSystemApi. Constructed with no dependencies at plugin
/// registration; camera launch, permission requests, and the document
/// picker need a presented view controller, resolved from the foreground
/// scene at call time. All Pigeon completions are dispatched on the main
/// queue, and every work path runs off the main thread like Android's IO
/// executor.
final class IOSSystemApi: NSObject {
    private let pendingDefaults: UserDefaults
    private let publishJournal: PublishJournalStore
    private let metadataReader: ImageIOImageMetadataReader
    private let sandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    private let workQueue = DispatchQueue(label: "sitemark.system.io", qos: .userInitiated)

    private var cameraCallback: ((Result<CameraCaptureResult, Error>) -> Void)?
    private var cameraCaptureId: String?
    private var archiveCallback: ((Result<ArchiveSaveOutcome, Error>) -> Void)?
    private var archiveStagedURL: URL?
    private var permissionCallback: ((Result<LocationPermissionState, Error>) -> Void)?
    private var locationCallbacks: [(Result<LocationResult, Error>) -> Void] = []
    private var locationTimeout: DispatchWorkItem?
    private var requestedLocationTimeoutMillis: Int64 =
        IOSSystemApi.defaultLocationTimeoutMillis
    private lazy var locationManager = CLLocationManager()

    private enum Keys {
        static let locationPermissionRequested = "location_permission_requested"
    }

    static let defaultLocationTimeoutMillis: Int64 = 10_000

    override init() {
        let suiteName = CaptureSessionPolicy.preferencesName
        pendingDefaults =
            UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
        if let supportDirectory {
            try? FileManager.default.createDirectory(
                at: supportDirectory, withIntermediateDirectories: true)
        }
        publishJournal = PublishJournalStore(
            JournalFilePersistence(directory: supportDirectory ?? sandboxRoot))
        metadataReader = ImageIOImageMetadataReader()
        super.init()
    }

    /// Releases pending callbacks and stops in-flight work. The API stays
    /// usable for the headless paths after re-registration.
    func dispose() {
        cameraCallback = nil
        cameraCaptureId = nil
        archiveCallback = nil
        archiveStagedURL = nil
        permissionCallback = nil
        locationCallbacks.removeAll()
        locationTimeout?.cancel()
        locationTimeout = nil
    }

    // MARK: - Camera

    private var originalsDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? sandboxRoot
        return support.appendingPathComponent("originals", isDirectory: true)
    }

    /// Reads a pending-session string from the capture-recovery suite.
    private func pendingString(forKey key: String) -> String? {
        pendingDefaults.string(forKey: key)
    }

    private var captureStateStore: CaptureStateStore {
        UserDefaultsCaptureStateStore(defaults: pendingDefaults)
    }
}

/// The 2b production `CaptureStateStore`: UserDefaults writes are durable
/// across process death, which is the whole contract of the pending state.
final class UserDefaultsCaptureStateStore: CaptureStateStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func removeValues(forKey keys: [String]) -> Bool {
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        return true
    }
}

extension IOSSystemApi: SiteMarkSystemApi {
    func createCameraTarget(captureId: String) throws -> String {
        let directory = originalsDirectory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(
            try CaptureTargetPolicy.fileName(captureId: captureId))
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        // Mirror Android: the pending session is written with apply()
        // semantics here (durable enough), while clearPending below uses
        // the synchronous CaptureStateStore contract.
        pendingDefaults.set(captureId, forKey: CaptureSessionPolicy.keyCaptureId)
        pendingDefaults.set(target.path, forKey: CaptureSessionPolicy.keyCapturePath)
        return target.path
    }

    func launchCamera(
        captureId: String, completion: @escaping (Result<CameraCaptureResult, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            self.launchCameraOnMain(captureId: captureId, completion: completion)
        }
    }

    private func launchCameraOnMain(
        captureId: String, completion: @escaping (Result<CameraCaptureResult, Error>) -> Void
    ) {
        if cameraCallback != nil {
            completion(.failure(PolicyError.cameraCaptureAlreadyActive))
            return
        }
        let targetPath: String
        do {
            targetPath = try preparedTarget(captureId: captureId)
        } catch {
            completion(.failure(error))
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            completion(
                .success(
                    CameraCaptureResult(
                        outcome: .failed,
                        outputPath: targetPath,
                        errorMessage: "No camera is available on this device")))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = self
        guard let presenter = Self.topViewController() else {
            completion(.failure(PolicyError.foregroundRequired))
            return
        }
        cameraCallback = completion
        cameraCaptureId = captureId
        presenter.present(picker, animated: true)
    }

    func recoverCameraCapture() throws -> RecoveredCameraCapture? {
        guard
            let captureId = pendingString(forKey: CaptureSessionPolicy.keyCaptureId),
            let path = pendingString(forKey: CaptureSessionPolicy.keyCapturePath)
        else {
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        let length = (attributes?[.size] as? Int64) ?? 0
        return RecoveredCameraCapture(
            captureId: captureId,
            outputPath: path,
            hasContent: CaptureTargetPolicy.recoveryDisposition(
                exists: exists, length: length) == .captured)
    }

    func finishCameraCapture(captureId: String, keepOriginal: Bool) throws {
        guard pendingString(forKey: CaptureSessionPolicy.keyCaptureId) == captureId else {
            return
        }
        let path = pendingString(forKey: CaptureSessionPolicy.keyCapturePath)
        _ = CaptureSessionPolicy.clearPending(captureStateStore)
        if !keepOriginal, let path {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func preparedTarget(captureId: String) throws -> String {
        guard pendingString(forKey: CaptureSessionPolicy.keyCaptureId) == captureId else {
            throw PolicyError.invalidCaptureId
        }
        guard
            let path = pendingString(forKey: CaptureSessionPolicy.keyCapturePath)
        else {
            throw PolicyError.privateFileMissingOrEmpty
        }
        let expected = originalsDirectory.appendingPathComponent(
            try CaptureTargetPolicy.fileName(captureId: captureId))
        let target = PrivateStoragePolicy.canonicalURL(path)
        guard target.path == PrivateStoragePolicy.canonicalURL(expected.path).path else {
            throw PolicyError.privateStorageRequired
        }
        return path
    }

    // MARK: - Location

    func getLocationPermissionState() throws -> LocationPermissionState {
        Self.mappedPermissionState(CLLocationManager.authorizationStatus())
    }

    func requestLocationPermission(
        completion: @escaping (Result<LocationPermissionState, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            let status = CLLocationManager.authorizationStatus()
            guard status == .notDetermined else {
                completion(.success(Self.mappedPermissionState(status)))
                return
            }
            if self.permissionCallback != nil {
                completion(.failure(PolicyError.locationRequestAlreadyActive))
                return
            }
            self.permissionCallback = completion
            self.locationManager.delegate = self
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    func openApplicationSettings() throws {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    func inspectImage(
        path: String, completion: @escaping (Result<ImageMetadataResult, Error>) -> Void
    ) {
        workQueue.async {
            let result = Result {
                let file = try PrivateStoragePolicy.validatedPrivateFile(
                    path: path, sandboxRoot: self.sandboxRoot)
                let metadata = try self.metadataReader.read(file: file)
                return ImageMetadataResult(
                    width: metadata.displayWidth,
                    height: metadata.displayHeight,
                    fileSizeBytes: metadata.fileSizeBytes,
                    mimeType: metadata.mimeType,
                    latitude: metadata.latitude,
                    longitude: metadata.longitude)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func requestCurrentLocation(
        timeoutMillis: Int64, completion: @escaping (Result<LocationResult, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            self.locationCallbacks.append(completion)
            guard self.locationCallbacks.count == 1 else {
                return
            }
            self.requestedLocationTimeoutMillis = min(max(timeoutMillis, 1_000), 30_000)
            self.startCurrentLocationOnMain()
        }
    }

    private func startCurrentLocationOnMain() {
        guard Self.mappedPermissionState(CLLocationManager.authorizationStatus()) == .granted
        else {
            finishLocation(
                LocationResult(outcome: .permissionDenied))
            return
        }
        locationManager.delegate = self
        locationManager.requestLocation()
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishLocation(LocationResult(outcome: .timeout))
        }
        locationTimeout = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(requestedLocationTimeoutMillis) / 1000.0,
            execute: timeout)
    }

    private func finishLocation(_ result: LocationResult) {
        guard !locationCallbacks.isEmpty else { return }
        let callbacks = locationCallbacks
        locationCallbacks.removeAll()
        locationTimeout?.cancel()
        locationTimeout = nil
        callbacks.forEach { $0(.success(result)) }
    }

    private static func mappedPermissionState(_ status: CLAuthorizationStatus)
        -> LocationPermissionState
    {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        case .notDetermined:
            // Android distinguishes "not asked" from "asked and explainable";
            // iOS only reports notDetermined, which maps to denied so the
            // Dart layer offers the request path.
            return .denied
        case .denied, .restricted:
            // An explicit iOS denial can only be undone in Settings, so it
            // maps to permanentlyDenied (design doc row 5).
            return .permanentlyDenied
        @unknown default:
            return .denied
        }
    }

    // MARK: - Publish / journal / delete

    func publishJpeg(
        sourcePath: String,
        displayName: String,
        captureId: String,
        publishedUri: String?,
        completion: @escaping (Result<MediaPublishResult, Error>) -> Void
    ) {
        workQueue.async {
            let result = Result {
                try self.publishJpegInternal(
                    sourcePath: sourcePath,
                    displayName: displayName,
                    captureId: captureId,
                    publishedUri: publishedUri)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func publishJpegInternal(
        sourcePath: String,
        displayName: String,
        captureId: String,
        publishedUri: String?
    ) throws -> MediaPublishResult {
        guard !captureId.isEmpty else {
            throw PolicyError.invalidCaptureId
        }
        let source = try PrivateStoragePolicy.validatedPrivateFile(
            path: sourcePath, sandboxRoot: sandboxRoot)
        let safeName = try PublishedImageNamePolicy.normalizedJpegName(displayName)
        // The ONLY assets this publish may supersede are explicit: the exact
        // identifier the caller's record previously published, plus the
        // COMPLETE leftover journal entry of an earlier crashed publish of
        // the SAME capture. Same-named rows owned by OTHER captures are
        // deliberately never candidates.
        let leftoverJournal = publishJournal.peek(captureId: captureId)
        var candidates: [String] = []
        if let publishedUri {
            candidates.append(publishedUri)
        }
        if let leftoverJournal {
            candidates.append(leftoverJournal.contentUri)
            candidates.append(contentsOf: leftoverJournal.supersededUris)
        }
        let supersededCandidates = Array(Set(candidates))
        let publisher = SafeMediaPublisher(
            store: PHPhotoPublishedImageStore(sourceFile: source),
            // Journal under the caller's stable capture ID so recovery
            // reconciles exactly the right database row even when several
            // records share a photo number after a backup restore.
            journal: { _, contentUri, supersededUris in
                self.publishJournal.record(
                    captureId: captureId,
                    contentUri: contentUri,
                    supersededUris: supersededUris)
            })
        let outcome = try publisher.publish(
            source: source,
            displayName: safeName,
            captureId: captureId,
            supersededCandidates: supersededCandidates)
        return MediaPublishResult(
            contentUri: outcome.contentUri,
            supersededUris: outcome.supersededUris)
    }

    func recoverPublishJournals() throws -> [RecoveredPublishJournal]? {
        publishJournal.recover().map { entry in
            RecoveredPublishJournal(
                captureId: entry.captureId,
                contentUri: entry.contentUri,
                supersededUris: entry.supersededUris)
        }
    }

    func clearPublishJournal(captureId: String, expectedContentUri: String) throws {
        publishJournal.clear(captureId: captureId, expectedContentUri: expectedContentUri)
    }

    func deletePublishedImage(
        contentUri: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        workQueue.async {
            let result = Result { try self.deletePublishedImageInternal(contentUri: contentUri) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func deletePublishedImageInternal(contentUri: String) throws {
        guard PublishedImageDeletePolicy.allowsDelete(localIdentifier: contentUri) else {
            throw PolicyError.invalidCaptureId
        }
        guard
            let asset = PHAsset.fetchAssets(
                withLocalIdentifiers: [contentUri], options: nil
            ).firstObject
        else {
            // The user may have deleted the photo themselves; a missing
            // asset is the desired end state (idempotent success).
            return
        }
        try PHPhotoPublishedImageStore.performDelete(asset: asset)
    }
    // MARK: - Archive save

    func saveArchive(
        sourcePath: String,
        suggestedName: String,
        completion: @escaping (Result<ArchiveSaveOutcome, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            self.saveArchiveOnMain(
                sourcePath: sourcePath,
                suggestedName: suggestedName,
                completion: completion)
        }
    }

    private func saveArchiveOnMain(
        sourcePath: String,
        suggestedName: String,
        completion: @escaping (Result<ArchiveSaveOutcome, Error>) -> Void
    ) {
        if archiveCallback != nil {
            completion(.failure(PolicyError.archiveSaveAlreadyActive))
            return
        }
        let source: URL
        do {
            source = try ArchiveSavePolicy.validateSource(
                sourcePath: sourcePath, dataDirectory: sandboxRoot)
            _ = try ArchiveSavePolicy.normalizeSuggestedName(suggestedName)
        } catch {
            completion(.failure(error))
            return
        }
        // Stage a copy under the normalized name: the document picker
        // exports the file under its own lastPathComponent.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitemark-archive-\(UUID().uuidString)", isDirectory: true)
        let staged = staging.appendingPathComponent(suggestedName)
        do {
            try FileManager.default.createDirectory(
                at: staging, withIntermediateDirectories: true)
            try ArchiveSavePolicy.copy(source: source, destination: staged)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            completion(.failure(error))
            return
        }
        guard let presenter = Self.topViewController() else {
            try? FileManager.default.removeItem(at: staging)
            completion(.failure(PolicyError.foregroundRequired))
            return
        }
        let picker = UIDocumentPickerViewController(
            forExporting: [staged], asCopy: true)
        picker.delegate = self
        archiveCallback = completion
        archiveStagedURL = staging
        presenter.present(picker, animated: true)
    }

    // MARK: - View controller resolution

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window: UIWindow?
        if #available(iOS 15.0, *) {
            window = scene?.keyWindow ?? scene?.windows.first
        } else {
            window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        }
        var root = window?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root
    }
}

// MARK: - UIImagePickerControllerDelegate

extension IOSSystemApi: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard let completion = cameraCallback, let captureId = cameraCaptureId else { return }
        cameraCallback = nil
        cameraCaptureId = nil
        let presenter = picker.presentingViewController
        let outcome: Result<CameraCaptureResult, Error> = {
            guard let image = info[.originalImage] as? UIImage,
                let data = image.jpegData(compressionQuality: 0.95),
                let target = pendingString(forKey: CaptureSessionPolicy.keyCapturePath)
            else {
                return .success(
                    CameraCaptureResult(
                        outcome: .failed,
                        outputPath: "",
                        errorMessage: "Unable to write the captured image"))
            }
            do {
                try data.write(to: URL(fileURLWithPath: target), options: .atomic)
                return .success(
                    CameraCaptureResult(outcome: .captured, outputPath: target))
            } catch {
                return .success(
                    CameraCaptureResult(
                        outcome: .failed,
                        outputPath: target,
                        errorMessage: "Unable to write the captured image"))
            }
        }()
        // Keep the pending session state for a captured image (the caller
        // decides via finishCameraCapture whether to keep the original);
        // a failed encode leaves nothing behind.
        if case .success(let value) = outcome, value.outcome != .captured {
            _ = CaptureSessionPolicy.clearPending(captureStateStore)
        }
        presenter?.dismiss(animated: true) {
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        guard let completion = cameraCallback, let captureId = cameraCaptureId else { return }
        cameraCallback = nil
        cameraCaptureId = nil
        // Mirror Android: a cancelled capture cleans the pending state and
        // the (empty) target file.
        try? finishCameraCapture(captureId: captureId, keepOriginal: false)
        let cancelled = Result<CameraCaptureResult, Error>.success(
            CameraCaptureResult(outcome: .cancelled, outputPath: ""))
        picker.presentingViewController?.dismiss(animated: true) {
            DispatchQueue.main.async { completion(cancelled) }
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension IOSSystemApi: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    {
        guard let completion = archiveCallback else { return }
        let staging = archiveStagedURL
        archiveCallback = nil
        archiveStagedURL = nil
        if let staging {
            try? FileManager.default.removeItem(at: staging)
        }
        completion(.success(.saved))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard let completion = archiveCallback else { return }
        let staging = archiveStagedURL
        archiveCallback = nil
        archiveStagedURL = nil
        if let staging {
            try? FileManager.default.removeItem(at: staging)
        }
        completion(.success(.cancelled))
    }
}

// MARK: - CLLocationManagerDelegate

extension IOSSystemApi: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishLocation(LocationResult(outcome: .unavailable))
            return
        }
        let accuracyAuthorization = CLLocationManager().accuracyAuthorization
        let outcome: LocationOutcome =
            accuracyAuthorization == .fullAccuracy ? .precise : .approximate
        finishLocation(
            LocationResult(
                outcome: outcome,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracyMeters: location.horizontalAccuracy,
                address: nil,
                errorMessage: nil))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        if clError?.code == .denied {
            finishLocation(
                LocationResult(outcome: .permissionDenied, errorMessage: error.localizedDescription))
        } else {
            finishLocation(
                LocationResult(outcome: .unavailable, errorMessage: error.localizedDescription))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let callback = permissionCallback else { return }
        permissionCallback = nil
        callback(.success(Self.mappedPermissionState(manager.authorizationStatus)))
    }
}
