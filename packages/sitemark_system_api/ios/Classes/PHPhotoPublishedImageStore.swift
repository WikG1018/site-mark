import Foundation
import Photos

/// `PublishedImageStore` adapter backed by PHPhotoLibrary.
///
/// PHPhotoLibrary has no pending-row concept, so per the design doc the
/// write-then-finalize dance collapses into a single creation request:
/// `insertPending` creates the asset from the prepared source file (an
/// atomic operation — success means the asset exists and is complete),
/// while `write` and `setPending` are no-ops. `delete` is idempotent: a
/// missing asset counts as the desired end state, mirroring Android's
/// already-deleted-row rule. The display name cannot be forced onto a
/// created asset (the library names files itself) — a platform delta
/// recorded in the design doc.
///
/// `performChanges` is asynchronous; the adapter blocks a worker thread on
/// a semaphore to keep SafeMediaPublisher's synchronous contract, exactly
/// like Android's blocking MediaStore calls.
public final class PHPhotoPublishedImageStore: PublishedImageStore {
    private let sourceFile: URL

    public init(sourceFile: URL) {
        self.sourceFile = sourceFile
    }

    public func insertPending(displayName: String) throws -> String {
        var identifier: String?
        var failure: Error?
        let completed = DispatchSemaphore(value: 0)
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromImage(
                atFileURL: self.sourceFile)
            identifier = request?.placeholderForCreatedAsset?.localIdentifier
        } completionHandler: { success, error in
            if !success {
                failure = error ?? PolicyError.unableToPersistPublishJournal
            }
            completed.signal()
        }
        completed.wait()
        if let failure {
            throw failure
        }
        guard let identifier, !identifier.isEmpty else {
            throw PolicyError.imageNotDecodable
        }
        return identifier
    }

    public func write(contentUri: String, source: URL) throws {
        // The creation request already copied the complete file into the
        // library; nothing left to write.
    }

    public func setPending(contentUri: String, pending: Bool) throws {
        // Created assets are immediately visible and complete.
    }

    public func delete(contentUri: String) throws {
        guard
            let asset = PHAsset.fetchAssets(
                withLocalIdentifiers: [contentUri],
                options: nil,
            ).firstObject
        else {
            // The user may have deleted the photo from the library
            // themselves. A missing asset is the desired end state, so this
            // is an idempotent success — failing here would keep the
            // cleanup task pending forever.
            return
        }
        try Self.performDelete(asset: asset)
    }

    /// Deletes one asset through the photo library. Standalone so the
    /// plugin can reuse it for `deletePublishedImage` without constructing
    /// a store (which is bound to a publish source file).
    static func performDelete(asset: PHAsset) throws {
        var failure: Error?
        let completed = DispatchSemaphore(value: 0)
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        } completionHandler: { success, error in
            if !success {
                failure = error ?? PolicyError.unableToPersistPublishJournal
            }
            completed.signal()
        }
        completed.wait()
        if let failure {
            throw failure
        }
    }
}
