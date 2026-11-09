import AppKit

/// 接系统「服务」菜单：任意 App 选中文字 → 右键 → 服务 → 用 BreezeLocal 朗读。
final class ServiceBridge: NSObject {
    static let shared = ServiceBridge()

    private func trace(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/breeze-service.log")
        let line = "[\(Date())] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// 由 App 启动时调用，确保在 Services 请求到来之前注册好
    func install() {
        NSApp.servicesProvider = self
        trace("servicesProvider installed, selector=\(NSStringFromSelector(#selector(readSelection(_:userData:error:))))")
    }

    @objc func readSelection(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text = pboard.string(forType: .string) ?? ""
        trace("readSelection called, chars=\(text.count)")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { @MainActor in
            AppState.shared.text = text
            AppState.shared.speakExternal(text)
        }
    }
}
