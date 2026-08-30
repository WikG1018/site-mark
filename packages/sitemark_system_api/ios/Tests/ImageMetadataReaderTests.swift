import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import SiteMarkSystemApiCore

final class ImageMetadataReaderTests: XCTestCase {
    private let reader = ImageIOImageMetadataReader()

    /// Renders a tiny JPEG with optional EXIF orientation and GPS tags.
    private func makeExifJpeg(
        width: Int, height: Int, orientation: Int?, latitude: Double?, longitude: Double?
    ) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sitemark-meta-\(UUID().uuidString).jpg")
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if let latitude, let longitude {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: abs(latitude),
                kCGImagePropertyGPSLatitudeRef: latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(longitude),
                kCGImagePropertyGPSLongitudeRef: longitude >= 0 ? "E" : "W",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testReadsOrientationCorrectedSizeAndGps() throws {
        let url = try makeExifJpeg(
            width: 8, height: 4, orientation: 6, latitude: 31.2304, longitude: 121.4737)
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try reader.read(file: url)

        // Orientation 6 (rotate 90°) swaps the display dimensions.
        XCTAssertEqual(metadata.displayWidth, 4)
        XCTAssertEqual(metadata.displayHeight, 8)
        XCTAssertEqual(metadata.mimeType, "image/jpeg")
        XCTAssertEqual(metadata.fileSizeBytes, Int64(try Data(contentsOf: url).count))
        XCTAssertEqual(metadata.latitude ?? 0, 31.2304, accuracy: 0.001)
        XCTAssertEqual(metadata.longitude ?? 0, 121.4737, accuracy: 0.001)
    }

    func testDefaultsToOrientationUpWithoutGps() throws {
        let url = try makeExifJpeg(
            width: 8, height: 4, orientation: nil, latitude: nil, longitude: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try reader.read(file: url)

        XCTAssertEqual(metadata.displayWidth, 8)
        XCTAssertEqual(metadata.displayHeight, 4)
        XCTAssertNil(metadata.latitude)
        XCTAssertNil(metadata.longitude)
    }

    func testSwapsDisplaySizeForEveryRotatingOrientation() {
        for orientation in [1, 2, 3, 4] {
            XCTAssertEqual(
                ImageOrientation.displaySize(encodedWidth: 8, encodedHeight: 4, orientation: orientation)
                    .width, 8)
        }
        for orientation in [5, 6, 7, 8] {
            XCTAssertEqual(
                ImageOrientation.displaySize(encodedWidth: 8, encodedHeight: 4, orientation: orientation)
                    .width, 4)
        }
    }

    func testRejectsNonImageFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sitemark-not-an-image-\(UUID().uuidString).jpg")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try reader.read(file: url)) { error in
            XCTAssertEqual(error as? PolicyError, .imageNotDecodable)
        }
    }
}
