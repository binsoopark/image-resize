import Accelerate
import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// 이미지 처리 파이프라인
///
/// 모든 변환은 **CIImage** 위에서만 수행한다. CGImage ↔ CIImage 왕복과
/// CGContext Y축 뒤집기는 좌표계 버그의 원인이므로 사용하지 않는다.
///
/// 단계:
/// 1. Load   — 파일 → CIImage (EXIF 보정, origin 정규화)
/// 2. Transform — 크롭 또는 stretch (CIImage transform)
/// 3. Flatten — (선택) 흰 배경 합성, 웹 `prepareCanvas`와 동일
/// 4. Export — `createCGImage` 단일 출구, (선택) vImage로 RGB 변환
enum ImageProcessor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Public entry

    /// 크롭/리사이즈와 투명도 제거를 하나의 CIImage 파이프라인으로 처리한다.
    static func process(
        from url: URL,
        mode: ProcessingMode,
        targetWidth: Int,
        targetHeight: Int,
        removeTransparency: Bool
    ) throws -> CGImage {
        try validateTargetSize(width: targetWidth, height: targetHeight)

        var image = try loadCIImage(from: url)
        image = try transform(image, mode: mode, targetWidth: targetWidth, targetHeight: targetHeight)

        if removeTransparency {
            image = flattenOnWhite(image)
            return try export(image, pixelFormat: .opaqueRGB, step: "투명도 제거")
        }

        let step = mode == .centerCrop ? "크롭" : "리사이즈"
        return try export(image, pixelFormat: .rgba, step: step)
    }

    static func loadCGImage(from url: URL) throws -> CGImage {
        let ciImage = try loadCIImage(from: url)
        return try export(ciImage, pixelFormat: .rgba, step: "미리보기")
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

    // MARK: - Step 1: Load

    private static func loadCIImage(from url: URL) throws -> CIImage {
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

    // MARK: - Step 2: Transform

    private static func transform(
        _ image: CIImage,
        mode: ProcessingMode,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> CIImage {
        switch mode {
        case .centerCrop:
            return try centerCropCIImage(image, targetWidth: targetWidth, targetHeight: targetHeight)
        case .stretch:
            return try stretchResizeCIImage(image, targetWidth: targetWidth, targetHeight: targetHeight)
        }
    }

    private static func centerCropCIImage(_ ciImage: CIImage, targetWidth: Int, targetHeight: Int) throws -> CIImage {
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

        if scale != 1 {
            image = normalizeOrigin(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        }

        let scaledW = srcW * scale
        let scaledH = srcH * scale
        let cropX = (scaledW - targetW) / 2
        let cropY = (scaledH - targetH) / 2

        image = image.cropped(to: CGRect(x: cropX, y: cropY, width: targetW, height: targetH))
        return normalizeOrigin(image.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY)))
    }

    private static func stretchResizeCIImage(_ image: CIImage, targetWidth: Int, targetHeight: Int) throws -> CIImage {
        let srcW = image.extent.width
        let srcH = image.extent.height
        guard srcW > 0, srcH > 0 else {
            throw ImageProcessorError.renderFailed(step: "리사이즈", reason: "원본 이미지 크기가 유효하지 않습니다.")
        }

        let scaleX = CGFloat(targetWidth) / srcW
        let scaleY = CGFloat(targetHeight) / srcH
        return normalizeOrigin(image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY)))
    }

    // MARK: - Step 3: Flatten (투명도 제거)

    /// 웹 `prepareCanvas`와 동일: 흰 배경 위에 합성한다. CIImage 단계에서만 수행한다.
    private static func flattenOnWhite(_ image: CIImage) -> CIImage {
        let rect = image.extent
        let background = CIImage(color: CIColor.white).cropped(to: rect)
        return normalizeOrigin(image.composited(over: background))
    }

    // MARK: - Step 4: Export

    private enum PixelFormat {
        case rgba
        case opaqueRGB
    }

    /// CIImage → CGImage 유일한 변환 경로
    private static func export(_ image: CIImage, pixelFormat: PixelFormat, step: String) throws -> CGImage {
        let normalized = normalizeOrigin(image)
        let rect = normalized.extent

        guard rect.width > 0, rect.height > 0 else {
            throw ImageProcessorError.renderFailed(step: step, reason: "렌더링 영역이 비어 있습니다.")
        }

        guard let cgImage = ciContext.createCGImage(normalized, from: rect) else {
            throw ImageProcessorError.renderFailed(
                step: step,
                reason: "Core Image 렌더링에 실패했습니다. (원본: \(Int(rect.width))×\(Int(rect.height)))"
            )
        }

        switch pixelFormat {
        case .rgba:
            return cgImage
        case .opaqueRGB:
            return try stripAlphaChannel(from: cgImage)
        }
    }

    /// vImage는 CGImage 좌표계를 내부에서 처리하므로 Y축 수동 뒤집기가 필요 없다.
    private static func stripAlphaChannel(from source: CGImage) throws -> CGImage {
        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        var sourceFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(colorSpace),
            bitmapInfo: source.bitmapInfo,
            version: 0,
            decode: nil,
            renderingIntent: source.renderingIntent
        )
        defer { sourceFormat.colorSpace.release() }

        var sourceBuffer = vImage_Buffer()
        defer {
            if sourceBuffer.data != nil {
                free(sourceBuffer.data)
            }
        }

        var error = vImageBuffer_InitWithCGImage(
            &sourceBuffer,
            &sourceFormat,
            nil,
            source,
            vImage_Flags(kvImageNoFlags)
        )
        guard error == kvImageNoError else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "픽셀 버퍼를 읽을 수 없습니다.")
        }

        var destBuffer = vImage_Buffer()
        defer {
            if destBuffer.data != nil {
                free(destBuffer.data)
            }
        }

        error = vImageBuffer_Init(
            &destBuffer,
            vImagePixelCount(source.height),
            vImagePixelCount(source.width),
            24,
            vImage_Flags(kvImageNoFlags)
        )
        guard error == kvImageNoError else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "RGB 버퍼를 만들 수 없습니다.")
        }

        switch source.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            error = vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destBuffer, vImage_Flags(kvImageNoFlags))
        default:
            error = vImageConvert_RGBA8888toRGB888(&sourceBuffer, &destBuffer, vImage_Flags(kvImageNoFlags))
        }
        guard error == kvImageNoError else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "알파 채널을 제거하지 못했습니다.")
        }

        var destFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            colorSpace: Unmanaged.passRetained(colorSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: source.renderingIntent
        )
        defer { destFormat.colorSpace.release() }

        var createError: vImage_Error = kvImageNoError
        guard let unmanaged = vImageCreateCGImageFromBuffer(
            &destBuffer,
            &destFormat,
            nil,
            nil,
            vImage_Flags(kvImageNoFlags),
            &createError
        ), createError == kvImageNoError else {
            throw ImageProcessorError.transparencyRemovalFailed(reason: "알파 없는 이미지로 변환하지 못했습니다.")
        }

        return unmanaged.takeRetainedValue()
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
