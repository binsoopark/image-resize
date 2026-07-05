import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Load

    static func loadCIImage(from url: URL) -> CIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        var ciImage = CIImage(cgImage: cgImage)

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientationRaw = properties[kCGImagePropertyOrientation] as? UInt32,
           orientationRaw != CGImagePropertyOrientation.up.rawValue {
            ciImage = ciImage.oriented(forExifOrientation: Int32(orientationRaw))
        }

        // extent.origin 이 (0, 0) 이 아닐 수 있어 정규화
        let origin = ciImage.extent.origin
        if origin.x != 0 || origin.y != 0 {
            ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }

        return ciImage
    }

    static func loadCGImage(from url: URL) -> CGImage? {
        guard let ciImage = loadCIImage(from: url) else { return nil }
        let extent = ciImage.extent
        return ciContext.createCGImage(ciImage, from: extent)
    }

    static func imageDimensions(at url: URL) -> (Int, Int)? {
        guard let ciImage = loadCIImage(from: url) else { return nil }
        let extent = ciImage.extent
        return (Int(extent.width.rounded()), Int(extent.height.rounded()))
    }

    static func makePreview(from url: URL, maxSize: CGFloat = 480) -> NSImage? {
        guard let cgImage = loadCGImage(from: url) else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxSize / max(width, height))
        let size = NSSize(width: width * scale, height: height * scale)
        let image = NSImage(cgImage: cgImage, size: size)
        return image
    }

    // MARK: - Center crop

    /// 1) EXIF 방향 보정된 이미지 기준으로 크기 계산
    /// 2) 목표보다 작으면 cover 방식으로 확대
    /// 3) 중심 기준으로 목표 크기만큼 크롭
    static func centerCrop(cgImage: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        centerCrop(ciImage: CIImage(cgImage: cgImage), targetWidth: targetWidth, targetHeight: targetHeight)
    }

    static func centerCrop(from url: URL, targetWidth: Int, targetHeight: Int) -> CGImage? {
        guard let ciImage = loadCIImage(from: url) else { return nil }
        return centerCrop(ciImage: ciImage, targetWidth: targetWidth, targetHeight: targetHeight)
    }

    private static func centerCrop(ciImage: CIImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let targetW = CGFloat(targetWidth)
        let targetH = CGFloat(targetHeight)

        var image = ciImage
        let origin = image.extent.origin
        if origin.x != 0 || origin.y != 0 {
            image = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }

        let srcW = image.extent.width
        let srcH = image.extent.height

        // 1) cover scale 계산 (웹과 동일)
        var scale: CGFloat = 1
        if srcW < targetW || srcH < targetH {
            scale = max(targetW / srcW, targetH / srcH)
        }

        let scaledW = srcW * scale
        let scaledH = srcH * scale

        // 2) 필요 시 확대
        if scale != 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // 3) 중심 크롭 (CIImage 좌표: 좌하단 원점)
        let cropX = (scaledW - targetW) / 2
        let cropY = (scaledH - targetH) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: targetW, height: targetH)

        image = image.cropped(to: cropRect)
        image = image.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))

        let outputRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        return ciContext.createCGImage(image, from: outputRect)
    }

    // MARK: - Stretch resize

    /// 1) EXIF 방향 보정
    /// 2) 비율 무시하고 목표 너비·높이에 맞춰 늘리거나 줄임
    static func stretchResize(from url: URL, targetWidth: Int, targetHeight: Int) -> CGImage? {
        guard var image = loadCIImage(from: url) else { return nil }

        let origin = image.extent.origin
        if origin.x != 0 || origin.y != 0 {
            image = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }

        let srcW = image.extent.width
        let srcH = image.extent.height
        let scaleX = CGFloat(targetWidth) / srcW
        let scaleY = CGFloat(targetHeight) / srcH

        image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let outputRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        return ciContext.createCGImage(image, from: outputRect)
    }

    // MARK: - Write

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

    static func outputFileName(
        for sourceURL: URL,
        format: OutputFormat,
        suffix: String = "cropped",
        width: Int,
        height: Int
    ) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        return "\(base)_\(suffix)_\(width)x\(height).\(format.fileExtension)"
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
