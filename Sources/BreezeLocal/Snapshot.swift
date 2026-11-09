import AppKit
import SwiftUI

/// 离屏渲染界面截图，用于在没有屏幕录制权限的环境里检查布局。
/// 用法：
///   BREEZE_SNAPSHOT=/tmp/ui.png ./BreezeLocal
///   BREEZE_SNAPSHOT_VIEW=voice|settings|help|add
///   BREEZE_THEME=dark
@MainActor
enum Snapshot {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["BREEZE_SNAPSHOT"] != nil
    }

    /// 自测：BREEZE_SPEAK_FILE=/tmp/text.txt 启动后合成该文件内容并退出
    static func runSpeakIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["BREEZE_SPEAK_FILE"] else { return }
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let state = AppState.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            state.generate(textOverride: text) { result in
                if let result {
                    print("RESULT path=\(result.path) duration=\(result.duration ?? 0) chars=\(result.chars ?? 0)")
                    exit(0)
                } else {
                    print("FAILED \(state.errorMessage ?? "unknown")")
                    exit(1)
                }
            }
        }
    }

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["BREEZE_SNAPSHOT"] else { return }
        let which = ProcessInfo.processInfo.environment["BREEZE_SNAPSHOT_VIEW"] ?? "main"
        let theme = ProcessInfo.processInfo.environment["BREEZE_THEME"] ?? "light"

        // 先把 AppState 建起来，让 sidecar 有时间返回模型列表，再渲染
        let state = AppState()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            let view: AnyView
            switch which {
            case "voice":
                view = AnyView(VoicePickerSheet().environmentObject(state))
            case "settings":
                view = AnyView(SettingsSheet().environmentObject(state))
            case "help":
                view = AnyView(HelpSheet().environmentObject(state))
            case "add":
                view = AnyView(AddModelSheet().environmentObject(state))
            case "history":
                view = AnyView(HistorySheet().environmentObject(state))
            case "about":
                view = AnyView(AboutSheet().environmentObject(state))
            default:
                view = AnyView(ContentView().environmentObject(state).frame(width: 380, height: 572))
            }

            if ProcessInfo.processInfo.environment["BREEZE_SNAPSHOT_DEMO"] != nil,
               let newest = state.history.first {
                state.lastOutput = newest.url
                state.lastResult = SpeakResult(path: newest.url.path, duration: 12.4, elapsed: 14.1,
                                               ttfa: 1.2, rtf: 1.3, loadSeconds: nil,
                                               peakMemoryGB: nil, chars: 88)
                state.generationStatus = "完成 · 12.4 秒音频 / 用时 14.1 秒"
            }

            let scheme: ColorScheme = theme == "dark" ? .dark : .light
            let renderer = ImageRenderer(
                content: view
                    .environment(\.colorScheme, scheme)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            renderer.scale = 2

            let appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)!
            var png: Data?
            appearance.performAsCurrentDrawingAppearance {
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff) {
                    png = rep.representation(using: .png, properties: [:])
                }
            }

            guard let png else {
                FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
                exit(2)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            print("snapshot: \(path)")
            exit(0)
        }
    }
}
