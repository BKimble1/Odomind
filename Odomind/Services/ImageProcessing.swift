import Foundation
import UIKit

/// Prepares a photo for storage.
///
/// Receipts are downscaled and re-encoded before they are written, for two
/// reasons: a backup carries its attachments inside it, and a 12-megapixel
/// photo of a receipt is no more readable than a 2,000-pixel one. Nothing is
/// uploaded, so this is purely about keeping the owner's own data manageable.
enum ImageProcessing {
    /// Longest edge, in pixels, of a stored attachment.
    static let maximumDimension: CGFloat = 2_000
    static let jpegQuality: CGFloat = 0.8

    struct Prepared {
        var data: Data
        var contentType: String
    }

    static func prepare(_ image: UIImage) -> Prepared? {
        let resized = downscale(image, to: maximumDimension)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { return nil }
        return Prepared(data: data, contentType: "image/jpeg")
    }

    /// Re-encodes arbitrary picked data, falling back to storing it as-is when
    /// it is not an image Odomind can read (a PDF receipt, for example).
    static func prepare(data: Data, contentType: String) -> Prepared {
        guard contentType.hasPrefix("image/"), let image = UIImage(data: data) else {
            return Prepared(data: data, contentType: contentType)
        }
        return prepare(image) ?? Prepared(data: data, contentType: contentType)
    }

    static func downscale(_ image: UIImage, to maximumDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maximumDimension, longestEdge > 0 else { return image }

        let scale = maximumDimension / longestEdge
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
