import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {
    static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func makePreview(from url: URL, maxSize: CGFloat = 480) -> NSImage? {
        guard let cgImage = loadCGImage(from: url) else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxSize / max(width, height))
        let size = NSSize(width: width * scale, height: height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            .draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }

    static func imageDimensions(at url: URL) -> (Int, Int)? {
        guard let cgImage = loadCGImage(from: url) else { return nil }
        return (cgImage.width, cgImage.height)
    }

    static func centerCrop(cgImage: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let targetW = CGFloat(targetWidth)
        let targetH = CGFloat(targetHeight)

        var scale: CGFloat = 1
        if srcW < targetW || srcH < targetH {
            scale = max(targetW / srcW, targetH / srcH)
        }

        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let cropX = (scaledW - targetW) / 2
        let cropY = (scaledH - targetH) / 2

        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: targetH)
        context.scaleBy(x: 1, y: -1)
        context.draw(
            cgImage,
            in: CGRect(x: -cropX, y: -cropY, width: scaledW, height: scaledH)
        )

        return context.makeImage()
    }

    static func write(cgImage: CGImage, to url: URL, format: OutputFormat, jpegQuality: CGFloat = 0.92) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ImageProcessorError.writeFailed
        }

        let options: [CFString: Any]
        switch format {
        case .png:
            options = [:]
        case .jpeg:
            options = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw ImageProcessorError.writeFailed
        }
    }

    static func outputFileName(for sourceURL: URL, format: OutputFormat) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        return "\(base)_cropped.\(format.fileExtension)"
    }
}

enum ImageProcessorError: LocalizedError {
    case invalidImage
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "이미지를 불러올 수 없습니다."
        case .writeFailed: return "파일 저장에 실패했습니다."
        }
    }
}
