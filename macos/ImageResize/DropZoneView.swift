import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject private var viewModel: ImageResizeViewModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                )

            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                Text("이미지를 여기에 드래그하세요")
                    .font(.headline)
                Text("또는 클릭해서 여러 파일 선택")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 28)
        }
        .frame(minHeight: 140)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { viewModel.addImagesViaPanel() }
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isTargeted) { providers in
            viewModel.loadFromDropProviders(providers)
            return true
        }
    }
}
