import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Metadata of one image, decoded by the pure core layer. The Pigeon glue
/// defines its own `ImageMetadataResult`; the Phase 2b plugin maps this
/// struct onto it so the core never imports Flutter.
public struct DecodedImageMetadata: Equatable {
    public let displayWidth: Int64
    public let displayHeight: Int64
    public let fileSizeBytes: Int64
    public let mimeType: String
    public let latitude: Double?
    public let longitude: Double?

    public init(
        displayWidth: Int64,
        displayHeight: Int64,
        fileSizeBytes: Int64,
        mimeType: String,
        latitude: Double?,
        longitude: Double?
    ) {
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.fileSizeBytes = fileSizeBytes
        self.mimeType = mimeType
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// EXIF orientation helpers. The numeric orientation values follow the
/// EXIF/CGImagePropertyOrientation standard (1–8); 5/6/7/8 swap the display
/// dimensions, exactly like AndroidXImageMetadataReader's ExifInterface
/// constants (TRANSPOSE=5, ROTATE_90=6, TRANSVERSE=7, ROTATE_270=8).
public enum ImageOrientation {
    public static func displaySize(encodedWidth: Int, encodedHeight: Int, orientation: Int)
        -> (width: Int, height: Int)
    {
        swapsDimensions(orientation)
            ? (encodedHeight, encodedWidth)
            : (encodedWidth, encodedHeight)
    }

    public static func swapsDimensions(_ orientation: Int) -> Bool {
        orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8
    }
}

/// Reads image metadata with ImageIO: bounds (no full decode), EXIF
/// orientation-corrected display size, MIME type, file size, and validated
/// EXIF GPS coordinates. Port of AndroidXImageMetadataReader.
public final class ImageIOImageMetadataReader {
    public init() {}

    public func read(file: URL) throws -> DecodedImageMetadata {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            throw PolicyError.imageNotDecodable
        }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let encodedWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let encodedHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            encodedWidth > 0, encodedHeight > 0
        else {
            throw PolicyError.imageNotDecodable
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let (width, height) = ImageOrientation.displaySize(
            encodedWidth: encodedWidth,
            encodedHeight: encodedHeight,
            orientation: orientation)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64)
            ?? 0
        var mimeType = "image/jpeg"
        if let typeIdentifier = CGImageSourceGetType(source) as String?,
            let type = UTType(typeIdentifier),
            let preferred = type.preferredMIMEType
        {
            mimeType = preferred
        }
        let gps = readValidatedGPS(properties: properties)
        return DecodedImageMetadata(
            displayWidth: Int64(width),
            displayHeight: Int64(height),
            fileSizeBytes: size ?? 0,
            mimeType: mimeType,
            latitude: gps?.latitude,
            longitude: gps?.longitude)
    }

    /// EXIF GPS coordinates with the same range validation as Android
    /// (latitude −90…90, longitude −180…180); nil unless both are present
    /// and in range. Hemisphere refs S/W negate the value.
    private func readValidatedGPS(properties: [CFString: Any]) -> (latitude: Double, longitude: Double)? {
        guard
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
            let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
            let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue,
            let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        else {
            return nil
        }
        let signedLatitude = latitudeRef.uppercased() == "S" ? -latitude : latitude
        let signedLongitude = longitudeRef.uppercased() == "W" ? -longitude : longitude
        guard (-90.0...90.0).contains(signedLatitude),
            (-180.0...180.0).contains(signedLongitude)
        else {
            return nil
        }
        return (signedLatitude, signedLongitude)
    }
}
