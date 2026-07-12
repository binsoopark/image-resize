import SwiftUI

struct ImageGridView: View {
    @EnvironmentObject private var viewModel: ImageResizeViewModel

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("미리보기")
                    .font(.headline)
                Text("\(viewModel.items.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(viewModel.items) { item in
                        ImageCardView(item: item)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

struct ImageCardView: View {
    @EnvironmentObject private var viewModel: ImageResizeViewModel
    let item: ImageResizeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let preview = item.previewImage {
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.secondary.opacity(0.08)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor))

                Text(item.status.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.status.badgeColor, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.outputWidth != nil, item.outputHeight != nil {
                    Text("원본 \(item.originalWidth) × \(item.originalHeight) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("→ \(item.outputWidth!) × \(item.outputHeight!) px")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text("원본 \(item.originalWidth) × \(item.originalHeight) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = item.status.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("저장") { viewModel.saveSingle(item) }
                        .disabled(item.processedURL == nil)
                    if item.processedURL != nil {
                        Button("Finder에서 보기") { viewModel.revealInFinder(item) }
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.status == .done ? Color.green.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
