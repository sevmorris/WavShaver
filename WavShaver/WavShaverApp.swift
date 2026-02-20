import SwiftUI

@main
struct WavShaverApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("WavShaver Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("WavShaver Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
