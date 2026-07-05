import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImageResizeViewModel: ObservableObject {
    @Published var items: [ImageResizeItem] = []
    @Published var targetWidth: Int = 800
    @Published var targetHeight: Int = 600
    @Published var outputFormat: OutputFormat = .png
    @Published var isProcessing = false
    @Published var showAlert = false
    @Published var alertMessage = ""

    private var outputDirectory: URL?

    var hasProcessedItems: Bool {
        items.contains { $0.processedURL != nil }
    }

    func addImagesViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "이미지 선택"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.addImageURLs(panel.urls)
            }
        }
    }

    func loadFromDropProviders(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier),
                       let url = item as? URL {
                        urls.append(url)
                    }
                }
            }
            addImageURLs(urls)
        }
    }

    func addImageURLs(_ urls: [URL]) {
        var added = 0
        for url in urls {
            guard isImageURL(url) else { continue }
            guard !items.contains(where: { $0.sourceURL == url }) else { continue }
            guard let (width, height) = ImageProcessor.imageDimensions(at: url) else { continue }
            let preview = ImageProcessor.makePreview(from: url)
            items.append(ImageResizeItem(sourceURL: url, originalWidth: width, originalHeight: height, previewImage: preview))
            added += 1
        }
        if added == 0 && !urls.isEmpty {
            presentAlert("이미지 파일만 추가할 수 있습니다.")
        }
    }

    func clearAll() {
        for index in items.indices {
            if let processed = items[index].processedURL {
                try? FileManager.default.removeItem(at: processed)
            }
        }
        items.removeAll()
        outputDirectory = nil
    }

    func processAll(mode: ProcessingMode) {
        guard targetWidth >= 1, targetHeight >= 1 else {
            presentAlert("너비와 높이는 1 이상이어야 합니다.")
            return
        }
        guard !items.isEmpty else { return }

        isProcessing = true
        let width = targetWidth
        let height = targetHeight
        let format = outputFormat
        let suffix = mode.fileSuffix

        Task {
            let tempDir = makeTempOutputDirectory()
            outputDirectory = tempDir

            for index in items.indices {
                items[index].status = .processing
                items[index].outputSuffix = nil
                items[index].outputWidth = nil
                items[index].outputHeight = nil
                if let oldURL = items[index].processedURL {
                    try? FileManager.default.removeItem(at: oldURL)
                    items[index].processedURL = nil
                }

                do {
                    let processed: CGImage?
                    switch mode {
                    case .centerCrop:
                        processed = ImageProcessor.centerCrop(
                            from: items[index].sourceURL,
                            targetWidth: width,
                            targetHeight: height
                        )
                    case .stretch:
                        processed = ImageProcessor.stretchResize(
                            from: items[index].sourceURL,
                            targetWidth: width,
                            targetHeight: height
                        )
                    }

                    guard let processed else {
                        throw ImageProcessorError.invalidImage
                    }

                    let fileName = ImageProcessor.outputFileName(
                        for: items[index].sourceURL,
                        format: format,
                        suffix: suffix,
                        width: width,
                        height: height
                    )
                    let destination = tempDir.appendingPathComponent(fileName)
                    try ImageProcessor.write(cgImage: processed, to: destination, format: format)

                    items[index].processedURL = destination
                    items[index].previewImage = NSImage(contentsOf: destination)
                    items[index].outputSuffix = suffix
                    items[index].outputWidth = width
                    items[index].outputHeight = height
                    items[index].status = .done
                } catch {
                    items[index].status = .error(error.localizedDescription)
                }
            }

            isProcessing = false
            presentAlert("모든 이미지 처리가 완료되었습니다.")
        }
    }

    func saveAll() {
        let processed = items.compactMap { item -> (ImageResizeItem, URL)? in
            guard let url = item.processedURL else { return nil }
            return (item, url)
        }
        guard !processed.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "저장할 폴더 선택"
        panel.prompt = "저장"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                self?.copyProcessedFiles(processed, to: folder)
            }
        }
    }

    func saveSingle(_ item: ImageResizeItem) {
        guard let sourceURL = item.processedURL else { return }
        let panel = NSSavePanel()
        panel.title = "이미지 저장"
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [outputFormat.utType]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                Task { @MainActor in
                    self.presentAlert("저장에 실패했습니다: \(error.localizedDescription)")
                }
            }
        }
    }

    func revealInFinder(_ item: ImageResizeItem) {
        guard let url = item.processedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyProcessedFiles(_ files: [(ImageResizeItem, URL)], to folder: URL) {
        var saved = 0
        for (_, sourceURL) in files {
            let destination = uniqueURL(in: folder, fileName: sourceURL.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                saved += 1
            } catch {
                presentAlert("저장 중 오류: \(error.localizedDescription)")
                return
            }
        }
        presentAlert("\(saved)개 파일을 저장했습니다.")
        NSWorkspace.shared.open(folder)
    }

    private func makeTempOutputDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("image-resize-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func uniqueURL(in folder: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = folder.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    private func isImageURL(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "webp", "gif", "heic", "tif", "tiff", "bmp"].contains(ext)
        }
        return type.conforms(to: .image)
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
