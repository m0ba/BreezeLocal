import AppKit
import SwiftUI

// MARK: - 设计令牌

private enum Palette {
    static let accentA = Color(red: 0.16, green: 0.47, blue: 0.93)
    static let accentB = Color(red: 0.10, green: 0.78, blue: 0.70)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentA, accentB], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var cardFill: Color { Color(nsColor: .controlBackgroundColor) }
    static var fieldFill: Color { Color(nsColor: .textBackgroundColor).opacity(0.65) }
    static var hairline: Color { Color.primary.opacity(0.07) }
}

private enum Metrics {
    static let windowWidth: CGFloat = 380
    static let windowHeight: CGFloat = 572
    static let cardRadius: CGFloat = 12
}

// MARK: - 基础组件

private struct LabelTag: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Palette.accentA.opacity(0.9))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompactPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.cardFill)
                .shadow(color: Color.black.opacity(0.045), radius: 1.2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.8)
        )
    }
}

private struct Card<Content: View>: View {
    let title: String?
    let symbol: String?
    let trailing: AnyView?
    let content: Content

    init(_ title: String? = nil,
         symbol: String? = nil,
         trailing: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || trailing != nil {
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.accentA.opacity(0.9))
                    }
                    Text(title ?? "")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.cardFill)
                .shadow(color: Color.black.opacity(0.05), radius: 1.5, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.8)
        )
    }
}

private struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var width: CGFloat? = nil
    var enabled: Bool = true
    var height: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(width: width, height: height)
            .background(
                Capsule().fill(Palette.accentGradient)
                    .opacity(enabled ? 1 : 0.35)
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct GhostButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .primary
    var enabled: Bool = true
    var height: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .medium)) }
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(enabled ? tint : tint.opacity(0.35))
            .padding(.horizontal, 9)
            .frame(height: height)
            .background(
                Capsule().fill(Color.primary.opacity(0.055))
            )
            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct IconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct Chip: View {
    let text: String
    var selected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 10, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(Palette.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
            )
    }
}

private struct SheetHeader: View {
    let title: String
    let subtitle: String?
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(hovering ? Color.primary.opacity(0.16) : Color.primary.opacity(0.07))
                    )
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .keyboardShortcut(.cancelAction)
            .help("关闭（Esc）")
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let hint: String
    let content: Content
    @State private var showHint = false

    init(_ label: String, hint: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Button { showHint.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHint, arrowEdge: .bottom) {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(width: 240, alignment: .leading)
                }
            }
            content
        }
    }
}

/// 截图模式下换成静态 Text，避免 TextEditor / TextField 在 ImageRenderer 里渲染成空白。
private struct InputBox: View {
    @Binding var text: String
    var height: CGFloat
    var placeholder: String
    var font: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.fieldFill)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 0.7)
            if Snapshot.isActive {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: font))
                    .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.55) : Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextEditor(text: $text)
                    .font(.system(size: font))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: font))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
    }
}

private struct SingleLineField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        if Snapshot.isActive {
            HStack {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 11))
                    .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.55) : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.hairline, lineWidth: 0.7))
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.hairline, lineWidth: 0.7))
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAddModel = false
    @State private var showDetail = false
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var showVoicePicker = false
    @State private var showHistory = false
    @State private var showDesign = false
    @State private var showClone = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            serviceCard
            composeCard
            modelCard
            logCard
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: Metrics.windowWidth, height: Metrics.windowHeight, alignment: .top)
        .background(background)
        .sheet(isPresented: $showAddModel) { AddModelSheet().environmentObject(state) }
        .sheet(isPresented: $showDetail) {
            if let model = state.selectedModel { ModelDetailSheet(model: model).environmentObject(state) }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(state) }
        .sheet(isPresented: $showHelp) { HelpSheet().environmentObject(state) }
        .sheet(isPresented: $showVoicePicker) { VoicePickerSheet().environmentObject(state) }
        .sheet(isPresented: $showHistory) { HistorySheet().environmentObject(state) }
        .sheet(isPresented: $showDesign) { VoiceCreateSheet(mode: "design").environmentObject(state) }
        .sheet(isPresented: $showClone) { VoiceCreateSheet(mode: "clone").environmentObject(state) }
        .onAppear {
            NSApp.servicesProvider = ServiceBridge.shared
            NSUpdateDynamicServices()
            HotKey.apply(KeyCombo.load())
            NSUpdateDynamicServices()
            HotKey.apply(KeyCombo.load())
            // 窗口尺寸固定，避免系统恢复上一次的旧尺寸留下大片空白
            DispatchQueue.main.async {
                NSApp.windows.first(where: { $0.canBecomeMain })?
                    .setContentSize(NSSize(width: Metrics.windowWidth, height: Metrics.windowHeight))
            }
        }
        .confirmationDialog("确定卸载选中的模型？", isPresented: $state.showRemoveConfirmation, titleVisibility: .visible) {
            Button("卸载", role: .destructive) { state.removeSelectedModel() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从本机删除模型文件，之后可以重新下载。")
        }
        .alert("出错了", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Palette.accentA.opacity(0.07),
                    Palette.accentB.opacity(0.025),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .clipped()
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accentGradient)
                    .frame(width: 30, height: 30)
                    .shadow(color: Palette.accentA.opacity(0.35), radius: 3, x: 0, y: 1)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("BreezeLocal").font(.system(size: 13.5, weight: .semibold))
                Text("本地语音合成 · Breeze TTS 2").font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5.5, height: 5.5)
                Text(statusText)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.05)))

            IconButton(symbol: "gearshape", help: "设置") { showSettings = true }
        }
        .frame(height: 32)
    }

    private var statusColor: Color {
        if state.isServiceRunning { return .green }
        if state.isServiceStarting { return .orange }
        return Color.secondary.opacity(0.4)
    }

    private var statusText: String {
        if state.isServiceRunning { return "运行中" }
        if state.isServiceStarting { return "启动中" }
        return "未启动"
    }

    // MARK: 服务

    private var serviceCard: some View {
        CompactPanel {
            HStack(spacing: 5) {
                LabelTag(text: "服务", symbol: "bolt.horizontal")
                Text(state.selectedModel?.displayName ?? "未选择模型")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let model = state.selectedModel {
                    Text(model.quantLabel)
                        .font(.system(size: 8.5, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Palette.accentA.opacity(0.12)))
                        .foregroundStyle(Palette.accentA)
                }
                IconButton(symbol: "info.circle", help: "模型详情") { showDetail = true }
                    .opacity(state.selectedModel == nil ? 0.3 : 1)
                Spacer(minLength: 4)
                if state.isServiceRunning || state.isServiceStarting {
                    GhostButton(title: state.isServiceStarting ? "启动中…" : "停止服务",
                                symbol: "stop.fill", height: 24) { state.stopService() }
                } else {
                    PrimaryButton(title: "启动服务", symbol: "play.fill", width: 86, height: 24) {
                        state.startService()
                    }
                }
            }

            HStack(spacing: 6) {
                Text("127.0.0.1:\(String(state.mcpPort))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text(state.statusMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: 合成台

    private var composeCard: some View {
        Card("合成台", symbol: "text.bubble",
             trailing: AnyView(
                Button { showVoicePicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accentA)
                        Text(state.selectedVoice?.name ?? "选择音色")
                            .font(.system(size: 10.5, weight: .medium))
                        if let category = state.selectedVoice?.category {
                            Text(category)
                                .font(.system(size: 8.5))
                                .foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("选择音色")
             )) {

            InputBox(
                text: $state.text,
                height: 92,
                placeholder: "输入要朗读的文字。中文可以加 [笑] [叹气] [咳嗽] 这类语气标记。"
            )

            HStack(spacing: 6) {
                Text("\(state.text.count) 字 · 约 \(String(format: "%.0f", state.estimatedSeconds)) 秒")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                GhostButton(title: "朗读剪贴板", symbol: "doc.on.clipboard", height: 24) {
                    state.speakClipboard()
                }
                .fixedSize()
                .help("把剪贴板里的文字读出来；也可在任意 App 选中文字后右键 → 服务 → 用 BreezeLocal 朗读")
                if state.isGenerating {
                    if state.segmentProgress.isEmpty {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    } else {
                        Text("第 \(state.segmentProgress) 段")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Palette.accentA)
                    }
                }
                PrimaryButton(
                    title: state.isGenerating ? "生成中…" : "生成语音",
                    symbol: "sparkles",
                    width: 100,
                    enabled: !state.isGenerating && !state.text.isEmpty
                ) { state.generate() }
                .keyboardShortcut(.return, modifiers: .command)
            }

            LabeledField("导演指令（可选）", hint: "用一句话告诉模型怎么演：情绪、语气、语速、距离感。例如“语速放慢，语气克制而严肃”“像在耳边轻声说，带一点笑意”。留空就用当前音色的默认感觉。") {
                SingleLineField(text: $state.instruction, placeholder: "例如：语速放慢，语气克制，句尾收干净")
            }

            HStack(spacing: 5) {
                ForEach(["语速放慢", "语气温柔", "压低声音", "更有激情"], id: \.self) { preset in
                    Chip(text: preset) {
                        state.instruction = state.instruction.isEmpty ? preset : state.instruction + "，" + preset
                    }
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Palette.hairline)

            if let url = state.lastOutput {
                HStack(spacing: 7) {
                    PrimaryButton(title: "重播", symbol: "play.fill", width: 78, height: 26) {
                        state.play(url)
                    }

                    GhostButton(title: "在文件夹中显示", symbol: "folder", height: 26) {
                        state.reveal(url)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    if let result = state.lastResult {
                        Text(String(format: "%.1fs · 用时 %.1fs", result.duration ?? 0, result.elapsed ?? 0))
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("生成后可在这里重播、在文件夹中显示")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(height: 26)
            }
        }
    }

    // MARK: 模型

    private var modelCard: some View {
        CompactPanel {
            HStack(spacing: 5) {
                LabelTag(text: "模型", symbol: "shippingbox")
                if let model = state.selectedModel {
                    Text(model.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(model.sizeText) · \(channelName(model.channel))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("还没有模型，点“添加模型”下载一个（国内建议魔搭通道）")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                IconButton(symbol: "clock.arrow.circlepath", help: "历史生成") { showHistory = true }
                if state.selectedModel != nil {
                    IconButton(symbol: "info.circle", help: "详情") { showDetail = true }
                    IconButton(symbol: "trash", help: "卸载") { state.requestRemoveSelectedModel() }
                }
            }

            if state.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: state.downloadProgress ?? 0)
                        .progressViewStyle(.linear)
                        .tint(Palette.accentA)
                    HStack(spacing: 6) {
                        Text(downloadLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        GhostButton(title: "取消", tint: .red, height: 22) { state.cancelDownload() }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    GhostButton(title: "添加模型", symbol: "plus", height: 24) { showAddModel = true }
                    GhostButton(title: state.isChecking ? "测速中…" : "测速", symbol: "speedometer",
                                enabled: !state.isChecking && state.selectedModel != nil, height: 24) { state.runCheck() }
                    Spacer(minLength: 0)
                    if let check = state.checkResult {
                        Text(String(format: "P50 %.1fs · 峰值 %.1fGB", check.p50, check.peakMemoryGB))
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var downloadLabel: String {
        let done = ByteCountFormatter.string(fromByteCount: state.downloadBytes, countStyle: .file)
        guard state.downloadTotalBytes > 0 else { return "已下载 \(done)" }
        let total = ByteCountFormatter.string(fromByteCount: state.downloadTotalBytes, countStyle: .file)
        return "\(Int((state.downloadProgress ?? 0) * 100))% · \(done) / \(total)"
    }

    private func channelName(_ channel: String?) -> String {
        switch channel {
        case "modelscope": return "魔搭"
        case "mirror": return "HF 镜像"
        case "local": return "本地导入"
        case "hf": return "HF 官方"
        default: return "本机"
        }
    }

    // MARK: 日志

    private var logCard: some View {
        CompactPanel {
            HStack(alignment: .top, spacing: 5) {
                LabelTag(text: "日志", symbol: "terminal")
                    .padding(.top, 1.5)
                VStack(alignment: .leading, spacing: 1.5) {
                    if state.logs.isEmpty {
                        Text("—")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(state.logs.suffix(2).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                Spacer(minLength: 4)
                IconButton(symbol: "square.and.arrow.up", help: "导出日志") { state.exportLogs() }
                IconButton(symbol: "trash", help: "清理下载缓存") { state.cleanCache() }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            PrimaryButton(title: copied ? "已复制给 AI" : "复制给 AI", symbol: copied ? "checkmark" : "doc.on.clipboard") {
                state.copyHandoff()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            }
            Spacer(minLength: 0)
            IconButton(symbol: "folder", help: "打开输出目录") { state.openOutputs() }
            IconButton(symbol: "questionmark.circle", help: "帮助") { showHelp = true }
        }
        .frame(height: 30)
    }
}

// MARK: - 音色选择

struct VoicePickerSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var category = "全部"
    @State private var previewingID: String?
    @State private var showCreate = false
    @State private var createMode = "design"

    private let categories = ["全部", "女声", "男声", "场景", "我的", "内置"]

    private var items: [VoiceRecord] {
        switch category {
        case "我的": return state.customVoices
        case "内置": return state.speakers
        case "全部": return state.voices + state.speakers
        default: return state.voices.filter { $0.category == category }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeader(title: "选择音色", subtitle: "预设由声音描述生成；「内置」是模型自带槽位，音色由模型决定")

            HStack(spacing: 5) {
                ForEach(categories, id: \.self) { item in
                    Chip(text: item, selected: category == item) { category = item }
                }
                Spacer(minLength: 0)
                GhostButton(title: "新建", symbol: "plus") { showCreate = true }
            }

            if Snapshot.isActive {
                VStack(spacing: 6) {
                    ForEach(items.prefix(9)) { voice in row(voice) }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(items) { voice in row(voice) }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 520)
        .sheet(isPresented: $showCreate) {
            VoiceCreateSheet(mode: createMode).environmentObject(state)
        }
    }

    private func row(_ voice: VoiceRecord) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Palette.accentA.opacity(voice.kind == "speaker" ? 0.08 : 0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: voice.kind == "speaker" ? "person.wave.2" : "waveform.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(voice.kind == "speaker" ? Color.secondary : Palette.accentA)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(voice.name).font(.system(size: 11.5, weight: .medium))
                    Text(voice.category ?? voice.kindLabel)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4).padding(.vertical, 0.5)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }
                Text(voice.desc ?? voice.instruct ?? "—")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if previewingID == voice.id {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else {
                Button { preview(voice) } label: {
                    Text("试听").font(.system(size: 9.5, weight: .medium)).foregroundStyle(Palette.accentA)
                }
                .buttonStyle(.plain)
            }

            Button {
                state.selectedVoiceID = voice.id
                dismiss()
            } label: {
                Text(state.selectedVoiceID == voice.id ? "已选" : "选用")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(state.selectedVoiceID == voice.id ? Color.white : Color.primary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        Capsule().fill(state.selectedVoiceID == voice.id
                                       ? AnyShapeStyle(Palette.accentGradient)
                                       : AnyShapeStyle(Color.primary.opacity(0.07)))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.022))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(state.selectedVoiceID == voice.id ? Palette.accentA.opacity(0.45) : Palette.hairline, lineWidth: 0.8)
        )
    }

    private func preview(_ voice: VoiceRecord) {
        previewingID = voice.id
        let sample = "你好，我是\(voice.name)。很高兴认识你，希望这个声音你会喜欢。"
        state.generate(voiceOverride: voice, textOverride: sample, instructOverride: nil) { _ in
            previewingID = nil
        }
    }
}

// MARK: - 历史

struct HistorySheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var sheetHeight: CGFloat {
        if state.history.isEmpty { return 392 }
        let rows = min(state.history.count, 6)
        return min(480, 190 + CGFloat(rows) * 52)
    }

    private var totalSize: String {
        let bytes = state.history.reduce(Int64(0)) { $0 + state.fileSize($1.url) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(
                title: "历史生成",
                subtitle: state.history.isEmpty ? "生成的音频会保存在数据目录的 outputs 下" : "\(state.history.count) 条 · 共 \(totalSize)"
            )

            if state.history.isEmpty {
                emptyState
            } else if Snapshot.isActive {
                VStack(spacing: 6) {
                    ForEach(state.history.prefix(6)) { item in historyRow(item) }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(state.history) { item in historyRow(item) }
                    }
                    .padding(.trailing, 2)
                }
            }

            HStack(spacing: 7) {
                GhostButton(title: "打开输出目录", symbol: "folder") { state.openOutputs() }
                Spacer()
                if !state.history.isEmpty {
                    Text("点播放试听，或到 Finder 里取文件")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(18)
        .frame(width: 470, height: sheetHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Palette.accentA.opacity(0.10))
                    .frame(width: 54, height: 54)
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.accentA.opacity(0.85))
            }
            Text("还没有生成过音频")
                .font(.system(size: 12.5, weight: .medium))
            Text("回到主窗口写一段文字，选个音色点「生成语音」，\n成品会自动出现在这里。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "去写一段", symbol: "square.and.pencil", width: 104) { dismiss() }
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    private func historyRow(_ item: OutputRecord) -> some View {
        HStack(spacing: 9) {
            Button { state.play(item.url) } label: {
                ZStack {
                    Circle().fill(Palette.accentA.opacity(0.12)).frame(width: 26, height: 26)
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.accentA)
                }
            }
            .buttonStyle(.plain)
            .help("播放")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                Text(meta(item))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            IconButton(symbol: "folder", help: "在文件夹中显示") { state.reveal(item.url) }
            IconButton(symbol: "trash", help: "删除", tint: .red.opacity(0.8)) { state.delete(item) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.hairline, lineWidth: 0.7))
    }

    private func meta(_ item: OutputRecord) -> String {
        let date = item.createdAt.formatted(date: .abbreviated, time: .shortened)
        let duration = state.audioDuration(item.url) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: state.fileSize(item.url), countStyle: .file)
        return String(format: "%@ · %.1f 秒 · %@", date, duration, size)
    }
}

// MARK: - 添加模型

struct AddModelSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var customRepo = ""
    @State private var channel = "modelscope"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeader(title: "添加模型", subtitle: "按平台推荐；macOS 直接下载，Windows / Linux 复制命令")

            if Snapshot.isActive {
                content(macLimit: 3, crossLimit: 3)
            } else {
                ScrollView(showsIndicators: false) {
                    content(macLimit: 3, crossLimit: 5)
                        .padding(.trailing, 2)
                }
            }
        }
        .padding(16)
        .frame(width: 500, height: 620)
    }

    @ViewBuilder
    private func content(macLimit: Int, crossLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("macOS 推荐（本机）")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)

            ForEach(CatalogModel.all.prefix(macLimit)) { item in
                macRow(item)
            }

            Divider().overlay(Palette.hairline)

            Text("Windows / Linux 推荐")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)

            ForEach(CrossPlatformModel.all.prefix(crossLimit)) { item in
                crossRow(item)
            }

            Divider().overlay(Palette.hairline)

            Text("自定义仓库").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                TextField("mlx-community/Breeze-TTS-2-mlx-8bit", text: $customRepo)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fieldFill))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.hairline, lineWidth: 0.7))

                Picker("", selection: $channel) {
                    Text("魔搭").tag("modelscope")
                    Text("HF 镜像").tag("mirror")
                    Text("HF 官方").tag("hf")
                }
                .labelsHidden().frame(width: 90).controlSize(.small)

                PrimaryButton(title: "下载") {
                    let repo = customRepo.trimmingCharacters(in: .whitespaces)
                    guard !repo.isEmpty else { return }
                    state.download(repo, channel: channel)
                    dismiss()
                }
            }

            HStack {
                GhostButton(title: "导入本地目录…", symbol: "folder.badge.plus", height: 26) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        state.importLocalModel(from: url)
                        dismiss()
                    }
                }
                Spacer()
                Text("权重许可：仅限研究与非商用")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func macRow(_ item: CatalogModel) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title).font(.system(size: 11.5, weight: .medium))
                    if item.recommended {
                        Text("推荐")
                            .font(.system(size: 8.5, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Palette.accentA.opacity(0.14)))
                            .foregroundStyle(Palette.accentA)
                    }
                }
                Text("\(item.sizeText) · \(item.memoryText)")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
                Text(item.detail).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            GhostButton(title: "魔搭", height: 24) { state.download(item.repo, channel: "modelscope"); dismiss() }
            GhostButton(title: "HF 镜像", height: 24) { state.download(item.repo, channel: "mirror"); dismiss() }
            GhostButton(title: "HF", height: 24) { state.download(item.repo, channel: "hf"); dismiss() }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.022)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.hairline, lineWidth: 0.7))
    }

    private func crossRow(_ item: CrossPlatformModel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title).font(.system(size: 11, weight: .medium))
                    if item.recommended {
                        Text("推荐")
                            .font(.system(size: 8.5, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.sizeText).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Text(item.engine).font(.system(size: 9.5)).foregroundStyle(.secondary)
                Text(item.note).font(.system(size: 9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                GhostButton(title: "复制命令", symbol: "doc.on.doc", height: 22) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.command, forType: .string)
                }
                GhostButton(title: "打开页面", symbol: "arrow.up.right", height: 22) {
                    if let url = URL(string: "https://huggingface.co/\(item.repo)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.018)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.hairline, lineWidth: 0.7))
    }
}

// MARK: - 模型详情

struct ModelDetailSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let model: ModelRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SheetHeader(title: model.displayName, subtitle: model.id)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("量化", model.quantLabel)
                row("大小", model.sizeText)
                row("来源", channelName(model.channel))
                row("安装时间", model.installedAt ?? "—")
                row("路径", model.path)
            }
            Text("卸载只删除模型目录，不影响已生成的音频。")
                .font(.system(size: 9.5)).foregroundStyle(.secondary)
            HStack {
                GhostButton(title: "在文件夹中显示", symbol: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: model.path))
                }
                Spacer()
                PrimaryButton(title: "测速", symbol: "speedometer") { state.runCheck(); dismiss() }
            }
        }
        .padding(16)
        .frame(width: 470)
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func channelName(_ channel: String?) -> String {
        switch channel {
        case "modelscope": return "魔搭"
        case "mirror": return "HF 镜像"
        case "local": return "本地导入"
        case "hf": return "HF 官方"
        default: return "—"
        }
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("BreezeLocal.theme") private var themeRaw = ThemeMode.auto.rawValue
    @State private var port = ""
    @State private var portError: String?
    @State private var showAbout = false
    @State private var combo = KeyCombo.load()
    @State private var recordingHotKey = false
    @State private var hotKeyMonitor: Any?
    @State private var hotKeyError: String?
    @StateObject private var updates = UpdateChecker()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "设置", subtitle: "外观、服务、维护与 AI 客户端")

            section("外观") {
                HStack(spacing: 6) {
                    ForEach(ThemeMode.allCases) { mode in
                        Button { themeRaw = mode.rawValue } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.symbol).font(.system(size: 10))
                                Text(mode.label).font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(themeRaw == mode.rawValue ? Color.white : Color.primary)
                            .padding(.horizontal, 11).frame(height: 26)
                            .background(
                                Capsule().fill(themeRaw == mode.rawValue
                                               ? AnyShapeStyle(Palette.accentGradient)
                                               : AnyShapeStyle(Color.primary.opacity(0.06)))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            section("服务") {
                HStack(spacing: 6) {
                    Text("端口").font(.system(size: 11))
                    TextField("8743", text: $port)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8).frame(width: 76, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fieldFill))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 0.7))
                    GhostButton(title: "保存", height: 24) {
                        portError = state.setPort(port)
                        if portError == nil { dismiss() }
                    }
                    if let portError {
                        Text(portError).font(.system(size: 9.5)).foregroundStyle(.red)
                    }
                    Spacer()
                }
                HStack(spacing: 5) {
                    Text("MCP").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(state.mcpEndpoint)
                        .font(.system(size: 9.5, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    IconButton(symbol: "doc.on.doc", help: "复制 MCP 地址") { state.copyEndpoint() }
                }
            }

            section("快捷键") {
                HStack(spacing: 6) {
                    Button { toggleRecording() } label: {
                        Text(recordingHotKey ? "请按下组合…" : combo.display)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(recordingHotKey ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 92, minHeight: 26)
                            .background(
                                Capsule().fill(recordingHotKey
                                               ? AnyShapeStyle(Palette.accentGradient)
                                               : AnyShapeStyle(Color.primary.opacity(0.06)))
                            )
                            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)

                    GhostButton(title: "恢复默认", height: 26) { applyCombo(.default) }
                    GhostButton(title: combo.isDisabled ? "已关闭" : "关闭", height: 26) { applyCombo(.disabled) }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text(hotKeyHint)
                        .font(.system(size: 9))
                        .foregroundStyle(hotKeyError == nil ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    GhostButton(title: "刷新系统服务", height: 22) {
                        NSUpdateDynamicServices()
                    }
                    .help("右键“服务”菜单里没有「用 BreezeLocal 朗读」时点一下")
                }
            }

            section("输出格式") {
                HStack(spacing: 6) {
                    ForEach(["wav", "mp3", "ogg"], id: \.self) { format in
                        Button { state.exportFormat = format } label: {
                            Text(format.uppercased())
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(state.exportFormat == format ? Color.white : Color.primary)
                                .padding(.horizontal, 12).frame(height: 24)
                                .background(
                                    Capsule().fill(state.exportFormat == format
                                                   ? AnyShapeStyle(Palette.accentGradient)
                                                   : AnyShapeStyle(Color.primary.opacity(0.06)))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                Text("默认 WAV（无损、可 App 内试听）；MP3 兼容性最好；OGG 体积最小，但 App 内不能试听，会用系统播放器打开。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("维护") {
                HStack(spacing: 6) {
                    GhostButton(title: "清理缓存", symbol: "trash", height: 26) { state.cleanCache() }
                    GhostButton(title: "导出日志", symbol: "square.and.arrow.up", height: 26) { state.exportLogs() }
                    GhostButton(title: "打开数据目录", symbol: "folder", height: 26) { state.openDataFolder() }
                    Spacer()
                }
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(state.dataDir.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    IconButton(symbol: "doc.on.doc", help: "复制路径") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.dataDir.path, forType: .string)
                    }
                }
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.035)))
            }

            section("AI 客户端") {
                HStack(spacing: 6) {
                    GhostButton(title: "复制 Codex TOML", symbol: "doc.on.doc", height: 26) { state.copyCodexConfig() }
                    GhostButton(title: "复制 mcpServers JSON", symbol: "doc.on.doc", height: 26) { state.copyJSONConfig() }
                    Spacer()
                }
                Text("粘到客户端配置里，或回主窗口点「复制给 AI」一次带走全部说明。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            section("更新") {
                HStack(spacing: 6) {
                    Text("当前版本 \(updates.currentVersion)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if case .available = updates.state {
                        PrimaryButton(title: "下载更新", symbol: "arrow.down.circle", width: 104, height: 26) {
                            updates.downloadAndOpen()
                        }
                    }
                    GhostButton(title: "检查更新", symbol: "arrow.triangle.2.circlepath", height: 26) {
                        updates.check()
                    }
                }
                HStack(spacing: 5) {
                    updateStatusView
                    Spacer(minLength: 0)
                    if case .available = updates.state {
                        Button("更新说明") { updates.openReleasePage() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.accentA)
                    }
                }
            }

            Divider().overlay(Palette.hairline)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("BreezeLocal \(version)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                    Text("权重仅限研究与非商用").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
                GhostButton(title: "帮助与关于", symbol: "questionmark.circle", height: 26) { showAbout = true }
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear { port = String(state.mcpPort) }
        .onDisappear { stopRecording() }
        .sheet(isPresented: $showAbout) { AboutSheet().environmentObject(state) }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updates.state {
        case .idle:
            Text("从 GitHub Releases 检查新版本")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text("正在检查…").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("已是最新版本", systemImage: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
        case .available(let version):
            Label("发现新版本 v\(version)", systemImage: "sparkles")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Palette.accentA)
        case .downloading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text("正在下载…").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        case .downloaded(let path):
            Label("已下载到 \((path as NSString).lastPathComponent)", systemImage: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.green)
                .lineLimit(1)
                .truncationMode(.middle)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private var hotKeyHint: String {
        if let hotKeyError { return hotKeyError }
        if combo.isDisabled { return "已关闭全局快捷键；仍可用「朗读剪贴板」按钮或菜单栏。" }
        return "点上面的按钮，直接按下想用的组合（需带 ⌘⌥⌃⇧ 之一）；选中文字后 ⌘C，再按 \(combo.display) 朗读。"
    }

    private func toggleRecording() {
        if recordingHotKey {
            stopRecording()
            return
        }
        recordingHotKey = true
        hotKeyError = nil
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc 取消
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbon = KeyCombo.carbonModifiers(from: flags)
            guard carbon != 0 else {
                hotKeyError = "至少要带一个修饰键（⌘ ⌥ ⌃ ⇧）"
                return nil
            }
            let new = KeyCombo(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: carbon,
                display: KeyCombo.displayText(flags: flags, event: event)
            )
            applyCombo(new)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recordingHotKey = false
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
        }
        hotKeyMonitor = nil
    }

    private func applyCombo(_ new: KeyCombo) {
        combo = new
        new.save()
        hotKeyError = HotKey.apply(new) ? nil : HotKey.lastError
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            content()
        }
    }
}

// MARK: - 帮助

struct HelpSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                SheetHeader(title: "怎么用", subtitle: "四步出第一段语音")

                step(1, "下载模型", "「添加模型」里选 8bit（4.6GB），国内点魔搭，海外点 HF。")
                step(2, "启动服务", "首次启动要加载模型，约 10–30 秒；状态变绿就能合成。")
                step(3, "选音色 + 写文字", "音色按“甜美女生 / 御姐 / 磁性男声”这类听感命名，可先试听再选。中文可加 [笑] [叹气]。")
                step(4, "复制给 AI", "底部「复制给 AI」会把 MCP 地址、配置和工具说明一起复制，粘给 Codex / Claude 即可。")

                Divider().overlay(Palette.hairline)

                Text("划词朗读怎么用").font(.system(size: 11, weight: .semibold))
                Text("① 任意 App 里选中文字 → 右键 → 服务 → 「用 BreezeLocal 朗读」。\n② 或先 ⌘C 复制，点主界面「朗读剪贴板」，或直接按 ⌥⌘R（全局生效）。\n服务菜单由系统缓存，首次若没看到，把 App 放进「应用程序」再启动一次。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)

                Text("导演指令怎么写").font(.system(size: 11, weight: .semibold))
                Text("把它当成给演员说戏：说清情绪、意图和节奏，比堆形容词有效。\n“用耳语说，很轻、很紧张，像怕被人听见” 比 “戏剧化地耳语” 好。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)

                Text("许可提醒").font(.system(size: 11, weight: .semibold))
                Text("Breeze TTS 2 权重仅限研究与非商用；App 不内置权重，模型由你自己下载。商用需向 BreezeBlue 取得授权。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)

                Text("常见问题").font(.system(size: 11, weight: .semibold))
                Text("• 生成偏慢：M4 上大约 3–5 字/秒，长文建议分段。\n• 声音不像：克隆时逐字稿必须和录音完全一致，3–30 秒、干净、单人。\n• 端口被占用：设置里换端口后重启服务。\n• 第一次合成久：模型在加载，之后就快了。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(width: 470, height: 470)
    }

    private func step(_ index: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Palette.accentGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - 关于

struct AboutSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(title: "关于 BreezeLocal", subtitle: "本地语音合成 · 版本 \(version)")

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Palette.accentGradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: Palette.accentA.opacity(0.3), radius: 4, x: 0, y: 2)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BreezeLocal").font(.system(size: 14, weight: .semibold))
                    Text("把 Breeze TTS 2 跑在这台 Mac 上，模型、推理、MCP 服务都不出本机。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(Palette.hairline)

            VStack(alignment: .leading, spacing: 5) {
                item("waveform.circle.fill", "15 个音色预设", "甜美女生、御姐、磁性男声…每个都能先试听再选用")
                item("text.bubble", "文字设计音色", "一句描述造一个新声音，不用录音")
                item("person.wave.2", "录音克隆", "3–30 秒干净录音 + 逐字稿，复刻音色")
                item("text.alignleft", "长文分段", "按标点切段合成、段间留白，长文显示进度")
                item("cursorarrow.rays", "划词朗读", "系统服务菜单或菜单栏「朗读剪贴板」")
                item("point.3.connected.trianglepath.dotted", "MCP 工具", "breeze_speak / design / clone，给 Codex、Claude 调用")
            }

            Divider().overlay(Palette.hairline)

            VStack(alignment: .leading, spacing: 4) {
                Text("技术栈").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text("SwiftUI 外壳 + Python sidecar（mlx-audio / MLX / FastMCP），输出 24 kHz 单声道 WAV。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("模型权重受 BreezeBlue Research and Non-Commercial License 约束，仅限研究与非商用；App 不内置权重。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.dataDir.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 7) {
                GhostButton(title: "打开数据目录", symbol: "folder") { state.openDataFolder() }
                GhostButton(title: "复制 MCP 地址", symbol: "doc.on.doc") { state.copyEndpoint() }
                Spacer()
                PrimaryButton(title: "知道了") { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 470)
    }

    private func item(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Palette.accentA)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5, weight: .medium))
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 新建音色

struct VoiceCreateSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let mode: String

    @State private var name = ""
    @State private var detail = ""
    @State private var fileName = ""
    @State private var refPath: String?
    @State private var previewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeader(
                title: mode == "design" ? "用文字设计音色" : "克隆一段录音",
                subtitle: mode == "design" ? "写一段声音描述，模型按描述造音色" : "需要 3–30 秒干净录音 + 逐字一致的文稿"
            )

            LabeledField("音色名称", hint: "只在本机显示，例如“我的口播声”。") {
                SingleLineField(text: $name, placeholder: "例如：温柔女声")
            }

            if mode == "design" {
                LabeledField("声音描述", hint: "写清年龄、性别、音色质地、语气和语速。描述语言要和朗读文字一致。") {
                    InputBox(text: $detail, height: 76, placeholder: "例如：一位温柔自信的年轻女性，声音清晰，语气亲切，语速平缓。", font: 11)
                }
                Text("提示：加“带一点笑意”“气声多一点”“语速放慢”这类细节，差别会很明显。")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    GhostButton(title: "选择音频…", symbol: "waveform.badge.plus") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.wav, .audio, .mp3, .mpeg4Audio]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            fileName = url.lastPathComponent
                            refPath = state.importReferenceAudio(from: url)
                        }
                    }
                    Text(fileName.isEmpty ? "未选择（建议 WAV）" : fileName)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                LabeledField("逐字稿", hint: "必须和录音内容一字不差，包括重复和口误，否则音色会跑偏。") {
                    InputBox(text: $detail, height: 64, placeholder: "把录音里说的话原样打出来", font: 11)
                }
            }

            HStack(spacing: 7) {
                GhostButton(title: previewing ? "试听中…" : "试听一句", symbol: "play.fill", enabled: canPreview) {
                    previewing = true
                    let sample = "你好，这是这段音色的试听。"
                    var voice: VoiceRecord?
                    if mode == "design" {
                        voice = VoiceRecord(id: "preview", name: name.isEmpty ? "预览" : name, kind: "design",
                                            instruct: detail, refAudio: nil, refText: nil, createdAt: "")
                    } else if let refPath {
                        voice = VoiceRecord(id: "preview", name: name.isEmpty ? "预览" : name, kind: "clone",
                                            instruct: nil, refAudio: refPath, refText: detail, createdAt: "")
                    }
                    state.generate(voiceOverride: voice, textOverride: sample, instructOverride: nil) { _ in
                        previewing = false
                    }
                }
                Spacer()
                PrimaryButton(title: "保存音色", enabled: canSave) {
                    state.addVoice(
                        name: name,
                        kind: mode,
                        instruct: mode == "design" ? detail : nil,
                        refAudio: mode == "clone" ? refPath : nil,
                        refText: mode == "clone" ? detail : nil
                    )
                    dismiss()
                }
            }

            Text("试听走当前服务，需要先下载模型并启动服务。")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 450)
    }

    private var canPreview: Bool {
        if mode == "design" { return !detail.isEmpty }
        return refPath != nil && !detail.isEmpty
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && canPreview
    }
}
