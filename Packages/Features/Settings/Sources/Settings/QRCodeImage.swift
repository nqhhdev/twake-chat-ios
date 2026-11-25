import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeImage {
  static func make(from text: String, moduleSize: CGFloat = 12) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "H"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleSize, y: moduleSize))
    guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }

}
