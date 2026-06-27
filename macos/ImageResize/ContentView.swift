import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: ImageResizeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            DropZoneView()
            if !viewModel.items.isEmpty {
                ImageGridView()
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("알림", isPresented: $viewModel.showAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Image Resize")
                .font(.largeTitle.bold())
            Text("여러 이미지를 드래그하거나 추가한 뒤, 원하는 크기로 중심 기준 크롭합니다. 이미지가 목표보다 작으면 먼저 확대한 다음 크롭합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            LabeledContent("너비") {
                TextField("800", value: $viewModel.targetWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            Text("×")
                .foregroundStyle(.secondary)
            LabeledContent("높이") {
                TextField("600", value: $viewModel.targetHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            LabeledContent("형식") {
                Picker("형식", selection: $viewModel.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            Spacer()

            Button("이미지 추가") { viewModel.addImagesViaPanel() }
            Button("크롭 실행") { viewModel.processAll() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
            Button("전체 저장") { viewModel.saveAll() }
                .disabled(!viewModel.hasProcessedItems || viewModel.isProcessing)
            Button("초기화") { viewModel.clearAll() }
                .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
