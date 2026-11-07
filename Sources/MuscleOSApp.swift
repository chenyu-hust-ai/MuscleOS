import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MuscleOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = WorkoutStore()

    var body: some Scene {
        Window("MuscleOS", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建训练") { store.newRequested += 1 }
                    .keyboardShortcut("n", modifiers: .command)
                Button("导入记录…") { store.importRequested += 1 }
                    .keyboardShortcut("i", modifiers: .command)
                Button("导出数据…") { store.exportRequested += 1 }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}
