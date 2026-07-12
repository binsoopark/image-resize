import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Load

    static func loadCIImage(from url: URL) throws -> CIImage {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ImageProcessorError.loadFailed(
                fileName: url.lastPathComponent,
                reason: "파일을 읽을 수 없습니다. 다른 앱에서 열려 있거나 권한이 없을 수 있습니다."
            )
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageProcessorError.loadFailed(
                fileName: url.lastPathComponent,
                reason: "이미지 형식을 인식하지 못했습니다."
            )
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageProcessorError.loadFailed(
                fileName: url.lastPathComponent,
                reason: "이미지 데이터를 디코딩하지 못했습니다."
            )
        }

        var ciImage = CIImage(cgImage: cgImage)

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientationRaw = properties[kCGImagePropertyOrientation] as? UInt32,
           orientationRaw != CGImagePropertyOrientation.up.rawValue {
            ciImage = ciImage.oriented(forExifOrientation: Int32(orientationRaw))
        }

        return normalizeOrigin(ciImage)
    }

    static func loadCGImage(from url: URL) throws -> CGImage {
        let ciImage = try loadCIImage(from: url)
        return try renderCIImage(ciImage, in: ciImage.extent, step: "미리보기")
    }

    static func imageDimensions(at url: URL) -> (Int, Int)? {
        guard let ciImage = try? loadCIImage(from: url) else { return nil }
        let extent = ciImage.extent
        return (Int(extent.width.rounded()), Int(extent.height.rounded()))
    }

    static func makePreview(from url: URL, maxSize: CGFloat = 480) -> NSImage? {
        guard let cgImage = try? loadCGImage(from: url) else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxSize / max(width, height))
        let size = NSSize(width: width * scale, height: height * scale)
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Center crop

    static func centerCrop(from url: URL, targetWidth: Int, targetHeight: Int) throws -> CGImage {
        try validateTargetSize(width: targetWidth, height: targetHeight)
        let ciImage = try loadCIImage(from: url)
        return try centerCrop(ciImage: ciImage, targetWidth: targetWidth, targetHeight: targetHeight)
    }

    private static func centerCrop(ciImage: CIImage, targetWidth: Int, targetHeight: Int) throws -> CGImage {
        let targetW = CGFloat(targetWidth)
        let targetH = CGFloat(targetHeight)

        var image = normalizeOrigin(ciImage)
        let srcW = image.extent.width
        let srcH = image.extent.height

        guard srcW > 0, srcH > 0 else {
            throw ImageProcessorError.renderFailed(step: "크롭", reason: "원본 이미지 크기가 유효하지 않습니다.")
        }

        var scale: CGFloat = 1
        if srcW < targetW || srcH < targetH {
            scale = max(targetW / srcW, targetH / srcH)
        }

        let scaledW = srcW * scale
        let scaledH = srcH * scale

        if scale != 1 {
            image = normalizeOrigin(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        }

        let cropX = (scaledW - targetW) / 2
        let cropY = (scaledH - targetH) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: targetW, height: targetH)

        image = image.cropped(to: cropRect)
        image = normalizeOrigin(image.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY)))

        let outputRect = CGRect(x: 0, y: 0, width: targetW, height: targetH)
        return try renderCIImage(image, in: outputRect, step: "크롭")
    }

    // MARK: - Stretch resize

    static func stretchResize(from url: URL, targetWidth: Int, targetHeight: Int) throws -> CGImage {
        try validateTargetSize(width: targetWidth, height: targetHeight)
        var image = try loadCIImage(from: url)

        let srcW = image.extent.width
        let srcH = image.extent.height
        guard srcW > 0, srcH > 0 else {
            throw ImageProcessorError.renderFailed(step: "리사이즈", reason: "원본 이미지 크기가 유효하지 않습니다.")
        }

        let scaleX = CGFloat(targetWidth) / srcW
        let scaleY = CGFloat(targetHeight) / srcH
        image = normalizeOrigin(image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY)))

        let outputRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        return try renderCIImage(image, in: outputRect, step: "리사이즈")
    }

    // MARK: - Transparency

    static func removeTransparency(from cgImage: CGImage) throws -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "처리할 이미지 크기가 유효하지 않습니다.")
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let background = CIImage(color: CIColor.white).cropped(to: rect)
        let foreground = CIImage(cgImage: cgImage)
        let composited = foreground.composited(over: background)

        let flattened = try renderCIImage(composited, in: rect, step: "투명도 제거")
        return try copyAsOpaqueRGB(flattened)
    }

    private static func copyAsOpaqueRGB(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let size = NSSize(width: width, height: height)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "RGB 비트맵을 만들 수 없습니다.")
        }

        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "그래픽 컨텍스트를 만들 수 없습니다.")
        }

        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))

        var rect = NSRect(x: 0, y: 0, width: width, height: height)
        guard let opaque = rep.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "알파 없는 이미지로 변환하지 못했습니다.")
        }

        return opaque
    }

    // MARK: - Write

    static func write(cgImage: CGImage, to url: URL, format: OutputFormat, jpegQuality: CGFloat = 0.92) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ImageProcessorError.writeFailed(
                fileName: url.lastPathComponent,
                reason: "저장 위치를 만들 수 없습니다."
            )
        }

        let options: [CFString: Any]
        switch format {
        case .png:
            options = [:]
        case .jpeg:
            options = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.writeFailed(
                fileName: url.lastPathComponent,
                reason: "\(format.title) 형식으로 저장하지 못했습니다."
            )
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

    // MARK: - Helpers

    private static func validateTargetSize(width: Int, height: Int) throws {
        guard width >= 1, height >= 1 else {
            throw ImageProcessorError.invalidTargetSize(width: width, height: height)
        }
    }

    private static func normalizeOrigin(_ image: CIImage) -> CIImage {
        let origin = image.extent.origin
        guard origin.x != 0 || origin.y != 0 else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }

    private static func renderCIImage(_ image: CIImage, in rect: CGRect, step: String) throws -> CGImage {
        let normalized = normalizeOrigin(image)
        guard normalized.extent.width > 0, normalized.extent.height > 0 else {
            throw ImageProcessorError.renderFailed(step: step, reason: "렌더링 영역이 비어 있습니다.")
        }

        guard let cgImage = ciContext.createCGImage(normalized, from: rect) else {
            throw ImageProcessorError.renderFailed(
                step: step,
                reason: "Core Image 렌더링에 실패했습니다. (원본: \(Int(normalized.extent.width))×\(Int(normalized.extent.height)), 목표: \(Int(rect.width))×\(Int(rect.height)))"
            )
        }

        return cgImage
    }
}

enum ImageProcessorError: LocalizedError {
    case loadFailed(fileName: String, reason: String)
    case renderFailed(step: String, reason: String)
    case transparencyRemovalFailed(reason: String)
    case writeFailed(fileName: String, reason: String)
    case invalidTargetSize(width: Int, height: Int)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(fileName, reason):
            return "[불러오기] \(fileName): \(reason)"
        case let .renderFailed(step, reason):
            return "[\(step)] \(reason)"
        case let .transparencyRemovalFailed(reason):
            return "[투명도 제거] \(reason)"
        case let .writeFailed(fileName, reason):
            return "[저장] \(fileName): \(reason)"
        case let .invalidTargetSize(width, height):
            return "목표 크기가 올바르지 않습니다. (\(width)×\(height))"
        }
    }
}
