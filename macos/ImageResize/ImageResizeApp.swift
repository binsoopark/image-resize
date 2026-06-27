import SwiftUI

@main
struct ImageResizeApp: App {
    @StateObject private var viewModel = ImageResizeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 880, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("이미지 추가…") {
                    viewModel.addImagesViaPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
