import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示主窗口") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
        }
        Divider()
        if state.isServiceRunning || state.isServiceStarting {
            Button("停止服务") { state.stopService() }
        } else {
            Button("启动服务") { state.startService() }
        }
        Divider()
        Button("生成语音") { state.generate() }
            .disabled(state.isGenerating || state.text.isEmpty)
        Button("朗读剪贴板") { state.speakClipboard() }
            .disabled(state.isGenerating)
        Button("打开输出目录") { state.openOutputs() }
        Button("复制 MCP 地址") { state.copyEndpoint() }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}

@main
struct BreezeLocalApp: App {
    @StateObject private var state = AppState.shared
    @AppStorage("BreezeLocal.theme") private var themeRaw = ThemeMode.auto.rawValue

    init() {
        Snapshot.runIfRequested()
        Snapshot.runSpeakIfRequested()
        Snapshot.runUpdateCheckIfRequested()
    }

    private var colorScheme: ColorScheme? {
        switch ThemeMode(rawValue: themeRaw) ?? .auto {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 380, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("显示主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        MenuBarExtra("BreezeLocal", systemImage: "waveform") {
            MenuBarContent()
                .environmentObject(state)
        }
    }
}
