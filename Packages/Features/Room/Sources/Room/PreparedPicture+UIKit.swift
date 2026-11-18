import DesignSystem
import UIKit

extension PreparedPicture {
  /// Cuts the picture in `data` to its centre square, at most `maxSide` pixels, as JPEG; `nil` when it is not a
  /// picture. Lives in the feature because it uses UIKit (ADR 0005).
  public static func prepare(_ data: Data, maxSide: CGFloat = maxSide) -> PreparedPicture? {
    guard let image = UIImage(data: data) else { return nil }
    let pixels = CGSize(
      width: image.size.width * image.scale, height: image.size.height * image.scale)
    let square = min(pixels.width, pixels.height)
    guard square >= 1 else { return nil }
    let side = min(square, maxSide).rounded(.down)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
      .image { _ in
        // Draw the whole picture scaled so its short side fills the square, centred.
        let scale = side / square
        let drawn = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        image.draw(
          in: CGRect(
            x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width,
            height: drawn.height))
      }
    guard let jpeg = rendered.jpegData(compressionQuality: 0.85) else { return nil }
    return PreparedPicture(jpeg: jpeg, side: Int(side))
  }
}
