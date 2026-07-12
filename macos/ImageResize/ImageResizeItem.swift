import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ProcessingStatus: Equatable {
    case ready
    case processing
    case done
    case error(String)

    var label: String {
        switch self {
        case .ready: return "대기"
        case .processing: return "처리 중"
        case .done: return "완료"
        case .error: return "오류"
        }
    }

    var badgeColor: Color {
        switch self {
        case .ready: return .gray
        case .processing: return .orange
        case .done: return .green
        case .error: return .red
        }
    }

    var errorMessage: String? {
        if case let .error(message) = self { return message }
        return nil
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }
}

enum ProcessingMode {
    case centerCrop
    case stretch

    var fileSuffix: String {
        switch self {
        case .centerCrop: return "cropped"
        case .stretch: return "resized"
        }
    }
}

struct ImageResizeItem: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let fileName: String
    let originalWidth: Int
    let originalHeight: Int
    var status: ProcessingStatus = .ready
    var processedURL: URL?
    var previewImage: NSImage?
    var outputSuffix: String?
    var outputWidth: Int?
    var outputHeight: Int?

    init(sourceURL: URL, originalWidth: Int, originalHeight: Int, previewImage: NSImage?) {
        self.sourceURL = sourceURL
        self.fileName = sourceURL.lastPathComponent
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.previewImage = previewImage
    }
}
