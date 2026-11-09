import AppKit

/// 接系统「服务」菜单：在任意 App 里选中文字 → 右键 → 服务 → 用 BreezeLocal 朗读。
/// 需要在 Info.plist 里声明 NSServices（NSMessage = readSelection）。
final class ServiceBridge: NSObject {
    static let shared = ServiceBridge()

    @objc func readSelection(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        Task { @MainActor in
            AppState.shared.text = text
            AppState.shared.generate(textOverride: text)
        }
    }
}
