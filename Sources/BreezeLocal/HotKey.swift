import AppKit
import Carbon.HIToolbox

/// 一组全局快捷键：keyCode + Carbon 修饰键，display 只用于界面展示。
struct KeyCombo: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    var isDisabled: Bool { keyCode == 0 || carbonModifiers == 0 }

    static let `default` = KeyCombo(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(cmdKey | optionKey),
        display: "⌥⌘R"
    )

    static let disabled = KeyCombo(keyCode: 0, carbonModifiers: 0, display: "未设置")

    static func load() -> KeyCombo {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "BreezeLocal.hotkey.keyCode") != nil else { return .default }
        return KeyCombo(
            keyCode: UInt32(defaults.integer(forKey: "BreezeLocal.hotkey.keyCode")),
            carbonModifiers: UInt32(defaults.integer(forKey: "BreezeLocal.hotkey.modifiers")),
            display: defaults.string(forKey: "BreezeLocal.hotkey.display") ?? "未设置"
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "BreezeLocal.hotkey.keyCode")
        defaults.set(Int(carbonModifiers), forKey: "BreezeLocal.hotkey.modifiers")
        defaults.set(display, forKey: "BreezeLocal.hotkey.display")
    }

    /// 把 NSEvent 的修饰键转成 Carbon 掩码
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    static func displayText(flags: NSEvent.ModifierFlags, event: NSEvent) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyName(for: event)
    }

    private static func keyName(for event: NSEvent) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7",
            28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
            40: "K", 45: "N", 46: "M", 49: "Space", 36: "Return", 48: "Tab",
            51: "Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        if let name = names[event.keyCode] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}

private let hotKeySignature: OSType = 0x42524C5A // 'BRLZ'

private func breezeHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr, hotKeyID.signature == hotKeySignature {
        Task { @MainActor in
            AppState.shared.speakClipboard()
        }
    }
    return noErr
}

@MainActor
enum HotKey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerInstalled = false
    private(set) static var lastError: String?

    @discardableResult
    static func apply(_ combo: KeyCombo) -> Bool {
        installHandlerIfNeeded()
        unregister()
        guard !combo.isDisabled else {
            lastError = nil
            return true
        }
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            lastError = "这个组合已被其他程序占用，换一个试试"
            hotKeyRef = nil
            return false
        }
        lastError = nil
        return true
    }

    static func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            breezeHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        handlerInstalled = true
    }
}
