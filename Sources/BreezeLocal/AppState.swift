import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

private final class LineBuffer {
    private var text = ""

    func append(_ chunk: String) -> [String] {
        text += chunk
        var lines: [String] = []
        while let index = text.firstIndex(of: "\n") {
            lines.append(String(text[..<index]))
            text.removeSubrange(text.startIndex...index)
        }
        return lines
    }

    func flush() -> String? {
        guard !text.isEmpty else { return nil }
        defer { text = "" }
        return text
    }
}

private final class StreamedOutput {
    var lines: [String] = []
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - 模型

    @Published var models: [ModelRecord] = []
    @Published var selectedModelID: String? = UserDefaults.standard.string(forKey: "BreezeLocal.selectedModelID") {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: "BreezeLocal.selectedModelID") }
    }
    @Published var downloadSource = "mlx-community/Breeze-TTS-2-mlx-8bit"
    @Published var downloadChannel = "modelscope"
    @Published var isDownloading = false
    @Published var downloadProgress: Double?
    @Published var downloadBytes: Int64 = 0
    @Published var downloadTotalBytes: Int64 = 0
    @Published var isImporting = false

    // MARK: - 服务

    @Published var isServiceStarting = false
    @Published var isServiceRunning = false
    @Published var mcpPort: Int = {
        let stored = UserDefaults.standard.integer(forKey: "BreezeLocal.port")
        return stored >= 1024 ? stored : 8743
    }() {
        didSet { UserDefaults.standard.set(mcpPort, forKey: "BreezeLocal.port") }
    }

    // MARK: - 合成

    @Published var text = ""
    @Published var instruction = ""
    @Published var cfgScale: Double = 4
    @Published var selectedVoiceID = "preset.natural"
    @Published var isGenerating = false
    @Published var generationStatus = ""
    @Published var segmentProgress = ""
    @Published var lastResult: SpeakResult?
    @Published var lastOutput: URL?
    @Published var history: [OutputRecord] = []

    // MARK: - 音色

    @Published var customVoices: [VoiceRecord] = []
    @Published var exportFormat: String = UserDefaults.standard.string(forKey: "BreezeLocal.exportFormat") ?? "wav" {
        didSet { UserDefaults.standard.set(exportFormat, forKey: "BreezeLocal.exportFormat") }
    }
    /// MCP / AI 调用时建议使用的格式，会写进「复制给 AI」的交接文本
    @Published var aiFormat: String = UserDefaults.standard.string(forKey: "BreezeLocal.aiFormat") ?? "wav" {
        didSet { UserDefaults.standard.set(aiFormat, forKey: "BreezeLocal.aiFormat") }
    }
    @Published var showVoiceSheet = false
    @Published var showCloneSheet = false

    // MARK: - 通用

    @Published var statusMessage = "就绪"
    @Published var logs: [String] = []
    @Published var errorMessage: String?
    @Published var showRemoveConfirmation = false
    @Published var checkResult: CheckResult?
    @Published var isChecking = false

    let dataDir: URL
    let devRoot: URL

    private var serviceProcess: Process?
    private var downloadProcess: Process?
    private var cancelRequested = false
    private var player: AVAudioPlayer?

    init() {
        devRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        dataDir = Self.resolveDataDir(devRoot: devRoot)
        for sub in ["models", "outputs", "cache", "logs", "tmp", "voices"] {
            try? FileManager.default.createDirectory(
                at: dataDir.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        loadVoices()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopService() }
        }
        if let override = ProcessInfo.processInfo.environment["BREEZE_EXPORT_FORMAT"],
           ["wav", "mp3", "ogg"].contains(override.lowercased()) {
            exportFormat = override.lowercased()
        }
        appendLog("BreezeLocal 已启动")
        appendLog("数据目录：\(dataDir.path)")
        refreshModels()
        refreshHistory()
        if text.isEmpty {
            text = "你好，这里是 BreezeLocal。所有声音都在这台 Mac 上生成，不会上传到任何服务器。"
        }
    }

    private static func resolveDataDir(devRoot: URL) -> URL {
        if let env = ProcessInfo.processInfo.environment["BREEZE_DATA_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        let dev = devRoot.appendingPathComponent("data", isDirectory: true)
        // 只有未打包（swift run / .build 里的裸二进制）时才用项目内 data 目录
        let isBundled = Bundle.main.bundleURL.pathExtension == "app"
        if !isBundled, FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BreezeLocal", isDirectory: true)
    }

    // MARK: - 派生状态

    var selectedModel: ModelRecord? { models.first { $0.id == selectedModelID } }

    var isBusy: Bool { isDownloading || isImporting }

    var endpoint: String { "http://127.0.0.1:\(mcpPort)" }

    var mcpEndpoint: String { "\(endpoint)/mcp" }

    var voices: [VoiceRecord] {
        VoiceRecord.presets + customVoices
    }

    var speakers: [VoiceRecord] { VoiceRecord.speakers }

    var selectedVoice: VoiceRecord? { voices.first { $0.id == selectedVoiceID } }

    var estimatedSeconds: Double {
        // M4 实测约 3–5 字/秒，按 4 字/秒估算
        max(0.6, Double(text.count) / 4.0)
    }

    // MARK: - 模型列表

    func refreshModels(selecting modelID: String? = nil) {
        runSidecar(["list", "--data-dir", dataDir.path]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                let decoded = Self.decodeModelList(from: output)
                guard let decoded else {
                    self.appendLog("模型列表解析失败：\(output.prefix(120))")
                    self.errorMessage = "模型列表解析失败"
                    return
                }
                self.models = decoded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.appendLog("已发现 \(self.models.count) 个模型")
                if let modelID, self.models.contains(where: { $0.id == modelID }) {
                    self.selectedModelID = modelID
                } else if let current = self.selectedModelID, self.models.contains(where: { $0.id == current }) {
                    self.selectedModelID = current
                } else {
                    self.selectedModelID = self.models.first?.id
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func download(_ repo: String, channel: String) {
        guard !isDownloading else { return }
        downloadSource = repo
        downloadChannel = channel
        isDownloading = true
        cancelRequested = false
        downloadProgress = nil
        downloadBytes = 0
        downloadTotalBytes = 0
        errorMessage = nil
        statusMessage = "正在下载 \(repo)"
        appendLog("开始下载：\(repo)（\(channelLabel(channel))）")

        runSidecarStreaming(
            ["download", "--model", repo, "--channel", channel, "--data-dir", dataDir.path],
            onLine: { [weak self] line in self?.handleEventLine(line) }
        ) { [weak self] result in
            guard let self else { return }
            self.isDownloading = false
            self.downloadProgress = nil
            if self.cancelRequested {
                self.cancelRequested = false
                self.statusMessage = "已取消下载"
                self.appendLog("下载已取消（已下文件保留，下次可续传）")
                return
            }
            switch result {
            case .success:
                self.statusMessage = "模型下载完成"
                self.appendLog("模型下载完成")
                self.refreshModels(selecting: repo)
            case .failure(let error):
                self.statusMessage = "下载失败"
                self.errorMessage = error.localizedDescription
                self.appendLog("下载失败：\(error.localizedDescription)")
            }
        }
    }

    func cancelDownload() {
        guard isDownloading else { return }
        cancelRequested = true
        statusMessage = "正在取消…"
        downloadProcess?.terminate()
    }

    func importLocalModel(from url: URL) {
        isImporting = true
        errorMessage = nil
        statusMessage = "正在校验 \(url.lastPathComponent)"
        appendLog("导入本地模型：\(url.path)")
        runSidecar([
            "import", "--source", url.path, "--name", url.lastPathComponent, "--data-dir", dataDir.path
        ]) { [weak self] result in
            guard let self else { return }
            self.isImporting = false
            switch result {
            case .success:
                self.statusMessage = "模型已导入"
                self.appendLog("模型已导入")
                self.refreshModels()
            case .failure(let error):
                self.statusMessage = "导入失败"
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func requestRemoveSelectedModel() {
        guard selectedModel != nil else { return }
        showRemoveConfirmation = true
    }

    func removeSelectedModel() {
        guard let model = selectedModel else { return }
        if isServiceRunning { stopService() }
        statusMessage = "正在卸载 \(model.displayName)"
        runSidecar(["remove", "--model", model.id, "--data-dir", dataDir.path]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.appendLog("已卸载：\(model.displayName)")
                self.selectedModelID = nil
                self.refreshModels()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func runCheck() {
        guard let model = selectedModel, !isChecking else {
            if selectedModel == nil { errorMessage = "请先下载一个模型" }
            return
        }
        isChecking = true
        checkResult = nil
        statusMessage = "正在测速"
        appendLog("开始测速：\(model.displayName)")
        runSidecar(["check", "--model", model.id, "--data-dir", dataDir.path], onLine: { [weak self] line in
            self?.handleEventLine(line)
        }) { [weak self] result in
            guard let self else { return }
            self.isChecking = false
            switch result {
            case .success(let output):
                if let check = self.parseCheck(from: output) {
                    self.checkResult = check
                    self.statusMessage = String(format: "测速完成 · P50 %.2fs · 加载 %.1fs", check.p50, check.loadSeconds)
                } else {
                    self.statusMessage = "测速完成"
                }
            case .failure(let error):
                self.statusMessage = "测速失败"
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 服务

    func startService() {
        guard serviceProcess == nil else { return }
        guard let model = selectedModel else {
            traceExternal("startService: no model")
            errorMessage = "请先下载并选择一个模型"
            return
        }
        guard let invocation = sidecarInvocation() else {
            traceExternal("startService: sidecar missing, bundle=\(Bundle.main.resourceURL?.path ?? "-")")
            errorMessage = "找不到本地推理组件 breeze-sidecar"
            return
        }
        if isPortInUse(mcpPort) {
            // 端口已有服务（多半是上次退出残留的 sidecar）：直接复用，发请求失败再报错
            traceExternal("startService: port \(mcpPort) busy, reuse")
            isServiceRunning = true
            isServiceStarting = false
            statusMessage = "复用 \(mcpPort) 端口上已运行的服务"
            appendLog("端口 \(mcpPort) 上已有服务，直接复用")
            return
        }

        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.prefix + [
            "serve",
            "--model", model.id,
            "--port", "\(mcpPort)",
            "--data-dir", dataDir.path
        ]
        process.environment = sidecarEnvironment()

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingestServiceLog(text) }
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendLog("[stderr] \(text.trimmingCharacters(in: .whitespacesAndNewlines))") }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isServiceRunning = false
                self?.isServiceStarting = false
                self?.serviceProcess = nil
                self?.statusMessage = "服务已停止"
            }
        }

        do {
            try process.run()
            serviceProcess = process
            isServiceStarting = true
            isServiceRunning = false
            statusMessage = "服务启动中（首次要加载模型，约 10–30 秒）…"
            Task { @MainActor in
                for _ in 0..<180 {
                    guard self.serviceProcess != nil else { return }
                    if await self.checkHealth() {
                        self.isServiceStarting = false
                        self.isServiceRunning = true
                        self.statusMessage = "服务运行中"
                        self.appendLog("服务已启动：\(self.endpoint)")
                        return
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                self.isServiceStarting = false
                self.isServiceRunning = self.serviceProcess != nil
            }
        } catch {
            traceExternal("startService: run failed \(error.localizedDescription)")
            errorMessage = "启动失败：\(error.localizedDescription)"
        }
    }

    func stopService() {
        serviceProcess?.terminate()
        serviceProcess = nil
        isServiceRunning = false
        isServiceStarting = false
        statusMessage = "服务已停止"
    }

    func setPort(_ raw: String) -> String? {
        guard let port = Int(raw.trimmingCharacters(in: .whitespaces)) else { return "端口必须是数字" }
        guard (1024...65535).contains(port) else { return "端口范围 1024–65535" }
        if isServiceRunning || isServiceStarting { return "请先停止服务" }
        if isPortInUse(port) { return "端口 \(port) 已被占用" }
        mcpPort = port
        statusMessage = "端口已改为 \(port)"
        return nil
    }

    // MARK: - 合成

    func generate(voiceOverride: VoiceRecord? = nil, textOverride: String? = nil, instructOverride: String? = nil, completion: ((SpeakResult?) -> Void)? = nil) {
        guard !isGenerating else { return }
        let payloadText = (textOverride ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payloadText.isEmpty else {
            errorMessage = "先写点要读的文字"
            return
        }
        guard selectedModel != nil else {
            traceExternal("generate aborted: no model")
            errorMessage = "请先下载并选择一个模型"
            return
        }

        isGenerating = true
        generationStatus = "准备中…"
        errorMessage = nil

        let voice = voiceOverride ?? selectedVoice
        Task { @MainActor in
            if ProcessInfo.processInfo.environment["BREEZE_SKIP_SERVICE"] != nil {
                self.isServiceRunning = true
            }
            if !self.isServiceRunning {
                self.appendLog("服务未运行，自动启动…")
                self.startService()
                for _ in 0..<180 {
                    if self.isServiceRunning { break }
                    if self.serviceProcess == nil && !self.isServiceStarting { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            guard self.isServiceRunning else {
                self.isGenerating = false
                self.traceExternal("generate aborted: service not running")
                self.errorMessage = "服务没有起来，先点“启动服务”看看日志"
                completion?(nil)
                return
            }

            self.generationStatus = "生成中…"
            var body: [String: Any] = [
                "text": payloadText,
                "cfg_scale": self.cfgScale,
                "temperature": 0.9
            ]
            let extra = instructOverride ?? (self.instruction.isEmpty ? nil : self.instruction)
            if let voice {
                switch voice.kind {
                case "speaker":
                    body["voice"] = voice.id.replacingOccurrences(of: "speaker.", with: "")
                    if let extra { body["instruct"] = extra }
                case "preset", "design":
                    var parts: [String] = []
                    if let base = voice.instruct, !base.isEmpty { parts.append(base) }
                    if let extra, !extra.isEmpty { parts.append(extra) }
                    if !parts.isEmpty {
                        body["instruct"] = parts.joined(separator: " ")
                        body["cfg_scale"] = 4.0
                    }
                case "clone":
                    body["ref_audio"] = voice.refAudio
                    body["ref_text"] = voice.refText
                    if let extra, !extra.isEmpty { body["instruct"] = extra }
                default:
                    if let extra { body["instruct"] = extra }
                }
            } else if let extra {
                body["instruct"] = extra
            }

            do {
                let started = Date()
                let segments = Self.splitForSynthesis(payloadText)
                var pcm = Data()
                var totalDuration = 0.0
                var firstTtfa = 0.0
                var lastRtf = 0.0

                for (index, segment) in segments.enumerated() {
                    if segments.count > 1 {
                        self.segmentProgress = "\(index + 1)/\(segments.count)"
                        self.generationStatus = "合成中 \(index + 1)/\(segments.count)"
                    }
                    var segmentBody = body
                    segmentBody["text"] = segment
                    let (data, response) = try await self.postSpeech(segmentBody)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let message = String(data: data, encoding: .utf8) ?? "未知错误"
                        throw NSError(domain: "BreezeLocal", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: message
                        ])
                    }
                    let segDuration = Double(http.value(forHTTPHeaderField: "X-Audio-Duration") ?? "") ?? 0
                    if firstTtfa == 0 {
                        firstTtfa = Double(http.value(forHTTPHeaderField: "X-Audio-TTFA") ?? "") ?? 0
                    }
                    lastRtf = Double(http.value(forHTTPHeaderField: "X-Audio-RTF") ?? "") ?? 0
                    totalDuration += segDuration
                    pcm.append(Self.pcmPayload(from: data))
                    if index < segments.count - 1 {
                        pcm.append(Self.silence(seconds: 0.28))
                    }
                }

                var url = self.outputURL(for: payloadText)
                try Self.writeWav(pcm: pcm, to: url)

                let format = self.exportFormat.lowercased()
                if format == "mp3" || format == "ogg" {
                    if let converted = await self.convertAudio(url, to: format) {
                        try? FileManager.default.removeItem(at: url)
                        url = converted
                    }
                }

                let elapsed = Date().timeIntervalSince(started)
                let result = SpeakResult(
                    path: url.path,
                    duration: totalDuration,
                    elapsed: elapsed,
                    ttfa: firstTtfa,
                    rtf: lastRtf,
                    loadSeconds: nil,
                    peakMemoryGB: nil,
                    chars: payloadText.count
                )
                self.lastResult = result
                self.lastOutput = url
                self.isGenerating = false
                self.segmentProgress = ""
                self.generationStatus = segments.count > 1
                    ? String(format: "完成 · %d 段 · %.1f 秒音频 / 用时 %.1f 秒", segments.count, totalDuration, elapsed)
                    : String(format: "完成 · %.1f 秒音频 / 用时 %.1f 秒", totalDuration, elapsed)
                self.statusMessage = "合成完成"
                self.appendLog(self.generationStatus)
                self.refreshHistory()
                self.play(url)
                completion?(result)
            } catch {
                self.isGenerating = false
                self.segmentProgress = ""
                self.generationStatus = "失败"
                let message = error.localizedDescription
                if message.contains("500") {
                    self.errorMessage = "服务返回 500：端口 \(self.mcpPort) 上可能是上次残留的服务。去设置换个端口，或退出 App 重开一次。"
                } else {
                    self.errorMessage = message
                }
                self.appendLog("合成失败：\(message)")
                completion?(nil)
            }
        }
    }

    private func postSpeech(_ body: [String: Any]) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(endpoint)/v1/audio/speech") else {
            throw NSError(domain: "BreezeLocal", code: 1, userInfo: [NSLocalizedDescriptionKey: "地址无效"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private func outputURL(for text: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        // 文件名只保留字母数字和汉字，避免标点导致 Finder 里难看
        let cleaned = String(text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || (0x4E00...0x9FFF).contains(scalar.value)
        }.prefix(12))
        let name = cleaned.isEmpty ? "breeze-\(stamp).wav" : "\(stamp)-\(cleaned).wav"
        return dataDir.appendingPathComponent("outputs").appendingPathComponent(name)
    }

    func refreshHistory() {
        let dir = dataDir.appendingPathComponent("outputs")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        history = files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .compactMap { url -> OutputRecord? in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return OutputRecord(url: url, text: url.deletingPathExtension().lastPathComponent, createdAt: date)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(40)
            .map { $0 }
    }

    private func convertAudio(_ url: URL, to format: String) async -> URL? {
        let dst = url.deletingPathExtension().appendingPathExtension(format)
        let result: Result<String, Error> = await withCheckedContinuation { continuation in
            runSidecar([
                "convert", "--in", url.path, "--out", dst.path,
                "--format", format, "--data-dir", dataDir.path
            ]) { res in
                continuation.resume(returning: res)
            }
        }
        switch result {
        case .success:
            appendLog("已转为 \(format.uppercased())：\(dst.lastPathComponent)")
            return dst
        case .failure(let error):
            appendLog("转码失败，保留 WAV：\(error.localizedDescription)")
            return nil
        }
    }

    func play(_ url: URL) {
        if url.pathExtension.lowercased() == "ogg" {
            NSWorkspace.shared.open(url)
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func delete(_ record: OutputRecord) {
        try? FileManager.default.removeItem(at: record.url)
        refreshHistory()
    }

    // MARK: - 音色库

    private func loadVoices() {
        let url = dataDir.appendingPathComponent("voices/voices.json")
        guard let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(VoiceLibrary.self, from: data) else {
            customVoices = []
            return
        }
        customVoices = library.voices
    }

    func saveVoices() {
        let library = VoiceLibrary(voices: customVoices)
        let url = dataDir.appendingPathComponent("voices/voices.json")
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: url)
        }
    }

    func addVoice(name: String, kind: String, instruct: String?, refAudio: String?, refText: String?) {
        let voice = VoiceRecord(
            id: "\(kind).\(UUID().uuidString.prefix(8))",
            name: name,
            kind: kind,
            instruct: instruct,
            refAudio: refAudio,
            refText: refText,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        customVoices.append(voice)
        saveVoices()
        selectedVoiceID = voice.id
        appendLog("已保存音色：\(name)（\(kind)）")
    }

    func deleteVoice(_ voice: VoiceRecord) {
        if let ref = voice.refAudio, ref.hasPrefix(dataDir.appendingPathComponent("voices").path) {
            try? FileManager.default.removeItem(atPath: ref)
        }
        customVoices.removeAll { $0.id == voice.id }
        saveVoices()
        if selectedVoiceID == voice.id { selectedVoiceID = "speaker.S0" }
    }

    func importReferenceAudio(from url: URL) -> String? {
        let dir = dataDir.appendingPathComponent("voices", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("ref-\(UUID().uuidString.prefix(8)).wav")
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target.path
        } catch {
            errorMessage = "导入参考音频失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 交付给 AI 的配置文本

    var codexConfigText: String {
        """
        [mcp_servers.breeze-local]
        url = "\(mcpEndpoint)"
        startup_timeout_sec = 30
        tool_timeout_sec = 600
        """
    }

    var jsonConfigText: String {
        """
        {
          "mcpServers": {
            "breeze-local": {
              "url": "\(mcpEndpoint)"
            }
          }
        }
        """
    }

    func aiHandoffText() -> String {
        let model = selectedModel?.displayName ?? "未选择模型"
        let path = selectedModel?.path ?? "未选择模型"
        return """
        请在这台 Mac 上配置下面这个本地 MCP 服务，并创建对应的使用规则。请直接根据下面的信息完成配置；如果客户端支持 MCP，请自动写入对应配置文件。

        ## MCP 服务
        - 名称：breeze-local
        - 传输：streamable-http
        - 地址：\(mcpEndpoint)
        - HTTP 接口：\(endpoint)
        - 数据目录：\(dataDir.path)
        - 当前模型：\(model)
        - 模型路径：\(path)
        - 采样率：24 kHz 单声道
        - 默认输出格式：\(aiFormat.uppercased())（可在设置里改）

        ## Codex 配置（~/.codex/config.toml）
        \(codexConfigText)

        ## Claude Desktop / Cursor / Cline 配置（mcpServers JSON）
        \(jsonConfigText)

        ## 可用工具
        - breeze_speak(text, voice?, instruct?, cfg_scale?, format?)：用本机模型合成语音，返回音频绝对路径；format 可选 wav（默认）/ mp3 / ogg。
        - breeze_design(text, description, cfg_scale?, format?)：用一句自然语言描述创造音色并朗读。
        - breeze_clone(text, ref_audio, ref_text, instruct?, cfg_scale?, format?)：用本地参考音频（3–30 秒）+ 逐字稿克隆音色。
        - breeze_status()：查看模型、采样率、内存占用。

        ## 使用规则
        1. 需要把文字变成语音时优先调用 breeze_speak，而不是调用云端 TTS。
        2. 中文文本可用 [笑]、[叹气]、[咳嗽]、[清嗓子] 等方括号标记；英文用 (laugh)、(sigh) 等圆括号标记。
        3. 需要特定情绪或语气时，把导演指令写进 instruct（例如“语速放慢，语气克制而严肃”）。
        4. 参考音频必须干净、单人、无背景音乐；ref_text 必须与音频内容逐字一致。
        5. 调用 breeze_speak / breeze_design / breeze_clone 时请传 format="\(aiFormat)"；不传则用 WAV。做语音机器人建议 mp3 或 ogg（体积约为 WAV 的 1/6）。
        6. MCP 生成的音频写在数据目录 outputs 下，只保留最近 5 条（可用环境变量 BREEZE_MCP_KEEP 调整），旧文件自动清理。
        7. 生成结果只作为素材，商用前请确认 Breeze TTS 2 权重的非商用许可。

        ## 验证方式
        1. 确认服务在跑：/usr/bin/nc -z 127.0.0.1 \(mcpPort)
        2. 列出工具，应看到 breeze_speak、breeze_design、breeze_clone、breeze_status。
        3. 调用 breeze_speak("你好，这是本地语音合成的测试。")，确认返回的 WAV 能播放。

        配置完成后请重启对应客户端，并告诉我实际写入的文件路径和验证结果。
        """
    }

    func copyHandoff() {
        copyToPasteboard(aiHandoffText())
        statusMessage = "已复制 AI 交接配置"
        appendLog("已复制 AI 交接配置")
    }

    func copyEndpoint() {
        copyToPasteboard(mcpEndpoint)
        statusMessage = "已复制 MCP 地址"
    }

    func copyCodexConfig() {
        copyToPasteboard(codexConfigText)
        statusMessage = "已复制 Codex TOML"
    }

    func copyJSONConfig() {
        copyToPasteboard(jsonConfigText)
        statusMessage = "已复制 mcpServers JSON"
    }

    // MARK: - 维护

    func cleanCache() {
        statusMessage = "正在清理缓存"
        runSidecar(["clean-cache", "--data-dir", dataDir.path]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.statusMessage = "缓存已清理（模型与输出未动）"
                self.appendLog(self.statusMessage)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func exportLogs() {
        let panel = NSSavePanel()
        panel.title = "导出运行日志"
        panel.nameFieldStringValue = "BreezeLocal-log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? logs.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        statusMessage = "日志已导出"
    }

    func openDataFolder() { NSWorkspace.shared.open(dataDir) }
    func openOutputs() { NSWorkspace.shared.open(dataDir.appendingPathComponent("outputs")) }

    // MARK: - 进程与日志

    private struct Invocation {
        var executable: URL
        var prefix: [String]
    }

    private func sidecarInvocation() -> Invocation? {
        if let env = ProcessInfo.processInfo.environment["BREEZE_SIDECAR_PATH"],
           FileManager.default.isExecutableFile(atPath: env) {
            return Invocation(executable: URL(fileURLWithPath: env), prefix: [])
        }
        if let resource = Bundle.main.resourceURL?
            .appendingPathComponent("breeze-sidecar", isDirectory: true)
            .appendingPathComponent("breeze-sidecar"),
           FileManager.default.isExecutableFile(atPath: resource.path) {
            return Invocation(executable: resource, prefix: [])
        }
        let script = devRoot.appendingPathComponent("sidecar/breeze_sidecar.py")
        let python = devRoot.appendingPathComponent(".venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: python.path),
           FileManager.default.fileExists(atPath: script.path) {
            return Invocation(executable: python, prefix: [script.path])
        }
        return nil
    }

    private func sidecarEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HF_HOME"] = dataDir.appendingPathComponent("cache/huggingface").path
        env["HF_HUB_CACHE"] = dataDir.appendingPathComponent("cache/huggingface/hub").path
        env["XDG_CACHE_HOME"] = dataDir.appendingPathComponent("cache/xdg").path
        env["TMPDIR"] = dataDir.appendingPathComponent("tmp").path
        env["UV_CACHE_DIR"] = dataDir.appendingPathComponent("cache/uv").path
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    private func runSidecar(
        _ arguments: [String],
        onLine: ((String) -> Void)? = nil,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        guard let invocation = sidecarInvocation() else {
            Task { @MainActor in
                completion(.failure(NSError(domain: "BreezeLocal", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "找不到 breeze-sidecar，请先运行 scripts/build-sidecar.sh 或用开发环境启动"
                ])))
                self.appendLog("找不到 breeze-sidecar")
            }
            return
        }
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.prefix + arguments
        process.environment = sidecarEnvironment()
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            Task { @MainActor in completion(.failure(error)) }
            return
        }

        // 一次性命令：等进程退出后整块读取，避免 readabilityHandler 与 waitUntilExit 抢数据
        DispatchQueue.global(qos: .userInitiated).async {
            let outData = output.fileHandleForReading.readDataToEndOfFile()
            let errData = error.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""
            Task { @MainActor in
                if let onLine {
                    for line in out.split(separator: "\n") {
                        onLine(String(line))
                    }
                }
                if process.terminationStatus == 0 {
                    completion(.success(out))
                } else {
                    let message = err.isEmpty ? out : err
                    if out.isEmpty && err.isEmpty {
                        self.appendLog("sidecar 无输出，退出码 \(process.terminationStatus)")
                    }
                    completion(.failure(NSError(domain: "BreezeLocal", code: Int(process.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: message.isEmpty ? "sidecar 退出码 \(process.terminationStatus)" : message
                    ])))
                }
            }
        }
    }

    private func runSidecarStreaming(
        _ arguments: [String],
        onLine: @escaping @MainActor (String) -> Void,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        guard let invocation = sidecarInvocation() else {
            Task { @MainActor in
                completion(.failure(NSError(domain: "BreezeLocal", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "找不到 breeze-sidecar"
                ])))
            }
            return
        }
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.prefix + arguments
        process.environment = sidecarEnvironment()
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        downloadProcess = process

        let buffer = LineBuffer()
        let collected = StreamedOutput()

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = buffer.append(text)
            Task { @MainActor in
                for line in lines {
                    collected.lines.append(line)
                    onLine(line)
                }
            }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                let line = "[stderr] \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
                collected.lines.append(line)
                onLine(line)
            }
        }
        process.terminationHandler = { [weak self] proc in
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            let rest = output.fileHandleForReading.readDataToEndOfFile()
            let errData = error.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let tailLines = buffer.append(String(data: rest, encoding: .utf8) ?? "")
            collected.lines.append(contentsOf: tailLines)
            let tail = buffer.flush()
            Task { @MainActor in
                for line in tailLines { collected.lines.append(line); onLine(line) }
                if let tail, !tail.isEmpty { collected.lines.append(tail); onLine(tail) }
                self?.downloadProcess = nil
                if proc.terminationStatus == 0 {
                    completion(.success(collected.lines.joined(separator: "\n")))
                } else {
                    completion(.failure(NSError(domain: "BreezeLocal", code: Int(proc.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: errText.isEmpty ? collected.lines.joined(separator: "\n") : errText
                    ])))
                }
            }
        }
        do {
            try process.run()
        } catch {
            downloadProcess = nil
            Task { @MainActor in completion(.failure(error)) }
        }
    }

    private func handleEventLine(_ line: String) {
        if line.hasPrefix("[stderr]") {
            appendLog(line)
            return
        }
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(SidecarEvent.self, from: data) else {
            return
        }
        switch event.type {
        case "progress":
            if let bytes = event.bytes { downloadBytes = bytes }
            if let total = event.total, total > 0 {
                downloadTotalBytes = total
                downloadProgress = min(1, Double(downloadBytes) / Double(total))
            }
        case "status":
            if let message = event.message {
                statusMessage = message
                appendLog(message)
            }
        case "error":
            if let message = event.message { errorMessage = message }
        default:
            break
        }
    }

    private func ingestServiceLog(_ chunk: String) {
        for line in chunk.split(separator: "\n") {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if text.hasPrefix("{") {
                handleEventLine(text)
            } else {
                appendLog(text)
            }
        }
    }

    private func parseCheck(from output: String) -> CheckResult? {
        for line in output.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(SidecarEvent.self, from: data) else { continue }
            if event.type == "done", let check = event.check { return check }
        }
        return nil
    }

    private static func decodeModelList(from output: String) -> [ModelRecord]? {
        for line in output.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(SidecarModelList.self, from: data) {
                return decoded.models
            }
        }
        return nil
    }

    private func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        logs.append(text)
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func channelLabel(_ channel: String) -> String {
        switch channel {
        case "modelscope": return "魔搭"
        case "mirror": return "HF 镜像"
        default: return "HF 官方"
        }
    }

    private func isPortInUse(_ port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-z", "127.0.0.1", "\(port)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func checkHealth() async -> Bool {
        guard let url = URL(string: "\(endpoint)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = object["ok"] as? Bool {
                return ok
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - 长文分段与 WAV 拼接

    /// 按句末标点切分，再合并到 maxLength 字以内，避免一段太长导致超时或漏字。
    static func splitForSynthesis(_ text: String, maxLength: Int = 90) -> [String] {
        let terminators = CharacterSet(charactersIn: "。！？!?；;\n")
        var sentences: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if terminators.contains(scalar) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { sentences.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        if sentences.isEmpty { sentences = [text] }

        var merged: [String] = []
        var buffer = ""
        for sentence in sentences {
            if buffer.count + sentence.count > maxLength, !buffer.isEmpty {
                merged.append(buffer)
                buffer = ""
            }
            buffer += sentence
        }
        if !buffer.isEmpty { merged.append(buffer) }

        return merged.flatMap { hardSplit($0, maxLength: maxLength) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func hardSplit(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        var pieces: [String] = []
        var buffer = ""
        for ch in text {
            buffer.append(ch)
            if buffer.count >= maxLength, "，,、 ".contains(ch) {
                pieces.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { pieces.append(buffer) }
        return pieces
    }

    /// 从 24kHz/16bit 单声道 WAV 里取出 PCM 数据段
    static func pcmPayload(from wav: Data) -> Data {
        let bytes = [UInt8](wav)
        guard bytes.count > 44 else { return Data() }
        func u32(_ i: Int) -> Int {
            Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
        }
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = u32(offset + 4)
            let start = offset + 8
            if id == "data" {
                let end = min(start + size, bytes.count)
                return start < end ? Data(bytes[start..<end]) : Data()
            }
            offset = start + size + (size % 2)
        }
        return Data(bytes.dropFirst(44))
    }

    static func silence(seconds: Double) -> Data {
        Data(count: Int(24_000 * seconds) * 2)
    }

    static func writeWav(pcm: Data, to url: URL) throws {
        var out = Data()
        let sampleRate = 24_000
        let channels = 1
        let bits = 16
        let byteRate = sampleRate * channels * bits / 8
        let blockAlign = channels * bits / 8
        out.append(contentsOf: Array("RIFF".utf8))
        out.appendLE(UInt32(36 + pcm.count))
        out.append(contentsOf: Array("WAVEfmt ".utf8))
        out.appendLE(UInt32(16))
        out.appendLE(UInt16(1))
        out.appendLE(UInt16(channels))
        out.appendLE(UInt32(sampleRate))
        out.appendLE(UInt32(byteRate))
        out.appendLE(UInt16(blockAlign))
        out.appendLE(UInt16(bits))
        out.append(contentsOf: Array("data".utf8))
        out.appendLE(UInt32(pcm.count))
        out.append(pcm)
        try out.write(to: url)
    }

    func traceExternal(_ message: String) {
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

    /// 来自系统服务 / 外部调用的朗读
    func speakExternal(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        traceExternal("speakExternal models=\(models.count) selected=\(selectedModel?.id ?? "nil")")
        self.text = text
        generate(textOverride: text)
    }

    /// 朗读剪贴板（菜单栏项用）
    func speakClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string) else {
            errorMessage = "剪贴板里没有文字"
            return
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "剪贴板里没有文字"
            return
        }
        text = value
        generate(textOverride: value)
    }

    func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    func audioDuration(_ url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
