import Foundation
import PDFKit
import UIKit

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

enum PDFExtractor {
    static func text(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let string = page.string, !string.isEmpty {
                pages.append(string)
            }
        }
        let text = pages.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }
}

extension NSRange {
    var isValid: Bool {
        location != NSNotFound && location >= 0 && length >= 0
    }
}
