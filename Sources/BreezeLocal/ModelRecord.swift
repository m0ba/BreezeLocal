import Foundation

struct ModelRecord: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var path: String
    var source: String
    var channel: String?
    var sizeBytes: Int64?
    var installedAt: String?

    var displayName: String { name }

    var sizeText: String {
        guard let sizeBytes, sizeBytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var quantLabel: String {
        if id.contains("4bit") { return "4bit" }
        if id.contains("8bit") { return "8bit" }
        if id.contains("bf16") { return "bf16" }
        return "custom"
    }
}

struct SidecarModelList: Codable {
    var models: [ModelRecord]
}

struct SpeakResult: Codable {
    var path: String
    var duration: Double?
    var elapsed: Double?
    var ttfa: Double?
    var rtf: Double?
    var loadSeconds: Double?
    var peakMemoryGB: Double?
    var chars: Int?
}

struct CheckSample: Codable, Identifiable {
    var name: String
    var chars: Int
    var ttfa: Double
    var elapsed: Double
    var rtf: Double

    var id: String { name }
}

struct CheckResult: Codable {
    var ok: Bool
    var model: String
    var loadSeconds: Double
    var peakMemoryGB: Double
    var p50: Double
    var min: Double
    var max: Double
    var samples: [CheckSample]
}

struct SidecarEvent: Codable {
    var type: String
    var message: String?
    var bytes: Int64?
    var bytesFreed: Int64?
    var total: Int64?
    var model: ModelRecord?
    var result: SpeakResult?
    var check: CheckResult?

    enum CodingKeys: String, CodingKey {
        case type, message, bytes, bytesFreed, total, model, result
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        bytes = try? c.decodeIfPresent(Int64.self, forKey: .bytes)
        bytesFreed = try? c.decodeIfPresent(Int64.self, forKey: .bytesFreed)
        total = try? c.decodeIfPresent(Int64.self, forKey: .total)
        model = try? c.decodeIfPresent(ModelRecord.self, forKey: .model)
        if let speak = try? c.decodeIfPresent(SpeakResult.self, forKey: .result) {
            result = speak
            check = nil
        } else {
            result = nil
            check = try? c.decodeIfPresent(CheckResult.self, forKey: .result)
        }
    }
}

/// 一个可下载模型的目录项：三通道链接由 sidecar 按仓库 ID 生成。
struct CatalogModel: Identifiable, Hashable {
    var id: String { repo }
    let repo: String
    let title: String
    let quant: String
    let sizeText: String
    let memoryText: String
    let detail: String
    let recommended: Bool

    static let all: [CatalogModel] = [
        CatalogModel(
            repo: "mlx-community/Breeze-TTS-2-mlx-8bit",
            title: "Breeze TTS 2 · 8bit",
            quant: "8bit",
            sizeText: "4.60 GB",
            memoryText: "约 6–8 GB 内存",
            detail: "音质接近原版，16GB 内存的默认选择",
            recommended: true
        ),
        CatalogModel(
            repo: "mlx-community/Breeze-TTS-2-mlx-4bit",
            title: "Breeze TTS 2 · 4bit",
            quant: "4bit",
            sizeText: "3.04 GB",
            memoryText: "约 4–5 GB 内存",
            detail: "最快、最省内存，8GB 机器也能跑",
            recommended: false
        ),
        CatalogModel(
            repo: "mlx-community/Breeze-TTS-2-mlx",
            title: "Breeze TTS 2 · bf16",
            quant: "bf16",
            sizeText: "7.63 GB",
            memoryText: "约 11–12 GB 内存",
            detail: "原精度，32GB 内存才建议",
            recommended: false
        )
    ]
}

struct OutputRecord: Identifiable, Hashable {
    let url: URL
    let text: String
    let createdAt: Date

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct VoiceRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// "preset" | "design" | "clone" | "speaker"
    var kind: String
    var instruct: String?
    var refAudio: String?
    var refText: String?
    var createdAt: String
    var category: String? = nil
    var desc: String? = nil

    var kindLabel: String {
        switch kind {
        case "preset": return "预设"
        case "design": return "设计"
        case "clone": return "克隆"
        case "speaker": return "内置"
        default: return kind
        }
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "自动"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

extension VoiceRecord {
    /// 音色预设：全部通过“声音描述”驱动，命名按听感，不依赖 S0–S9 的槽位含义。
    static let presets: [VoiceRecord] = [
        VoiceRecord(
            id: "preset.natural", name: "自然女声", kind: "preset", instruct:
                "一位二十五六岁的年轻女性，声音干净自然，语气亲切，语速适中，像日常聊天。",
            refAudio: nil, refText: nil, createdAt: "", category: "女声",
            desc: "干净自然，不端着，适合通用朗读"
        ),
        VoiceRecord(
            id: "preset.sweet", name: "甜美女生", kind: "preset", instruct:
                "一位声音甜美的年轻女生，音色明亮偏软，带一点鼻音和笑意，语速轻快，句尾微微上扬。",
            refAudio: nil, refText: nil, createdAt: "", category: "女声",
            desc: "明亮偏软，带笑意，适合短视频、种草"
        ),
        VoiceRecord(
            id: "preset.firstlove", name: "初恋女神", kind: "preset", instruct:
                "一位温柔安静的年轻女性，音色清透，气声偏多，语速偏慢，像在耳边轻声说话，带一点害羞。",
            refAudio: nil, refText: nil, createdAt: "", category: "女声",
            desc: "轻、软、气声多，适合情感文案、深夜电台"
        ),
        VoiceRecord(
            id: "preset.yujie", name: "御姐", kind: "preset", instruct:
                "一位三十岁左右的成熟女性，音色偏低、有磁性，语速从容，语气冷静自信，略带笑意。",
            refAudio: nil, refText: nil, createdAt: "", category: "女声",
            desc: "低沉磁性、从容自信，适合口播、职场"
        ),
        VoiceRecord(
            id: "preset.anchorwoman", name: "知性女主播", kind: "preset", instruct:
                "一位新闻女主播，声音清晰标准，吐字干净，语速稳定，语气客观克制，句读分明。",
            refAudio: nil, refText: nil, createdAt: "", category: "女声",
            desc: "清晰标准、客观克制，适合新闻、课程"
        ),
        VoiceRecord(
            id: "preset.magnetic", name: "磁性男声", kind: "preset", instruct:
                "一位三十多岁的男性，低音浑厚有磁性，语速偏慢，语气沉稳温和，共鸣靠胸腔。",
            refAudio: nil, refText: nil, createdAt: "", category: "男声",
            desc: "低音浑厚，适合旁白、广告、有声书"
        ),
        VoiceRecord(
            id: "preset.handsome", name: "帅气男音", kind: "preset", instruct:
                "一位二十多岁的年轻男性，音色干净利落，语气自信爽朗，语速稍快，咬字有弹性。",
            refAudio: nil, refText: nil, createdAt: "", category: "男声",
            desc: "干净利落、年轻爽朗，适合产品、Vlog"
        ),
        VoiceRecord(
            id: "preset.boyfriend", name: "温柔男友", kind: "preset", instruct:
                "一位二十多岁的男性，声音温柔偏低，语速慢，气息柔和，像在耐心安慰人。",
            refAudio: nil, refText: nil, createdAt: "", category: "男声",
            desc: "低声、慢速、耐心，适合情感、助眠"
        ),
        VoiceRecord(
            id: "preset.uncle", name: "沉稳大叔", kind: "preset", instruct:
                "一位五十岁左右的男性，声音低厚，略带沙哑，语速慢，语气有分量，像长辈讲故事。",
            refAudio: nil, refText: nil, createdAt: "", category: "男声",
            desc: "低厚略沙哑，适合纪录片、历史讲述"
        ),
        VoiceRecord(
            id: "preset.teen", name: "活力少年", kind: "preset", instruct:
                "一位十七八岁的男生，音色明亮偏薄，语气跳脱有活力，语速快，句尾上扬。",
            refAudio: nil, refText: nil, createdAt: "", category: "男声",
            desc: "明亮跳脱，适合二次元、游戏解说"
        ),
        VoiceRecord(
            id: "preset.documentary", name: "纪录片旁白", kind: "preset", instruct:
                "纪录片旁白，中低音，声音平稳克制，语速慢而均匀，句间留白，不带个人情绪。",
            refAudio: nil, refText: nil, createdAt: "", category: "场景",
            desc: "平稳克制、句间留白，适合纪录片"
        ),
        VoiceRecord(
            id: "preset.radio", name: "深夜电台", kind: "preset", instruct:
                "深夜电台主持人，声音低而柔，气声明显，语速很慢，像隔着耳机轻声说话。",
            refAudio: nil, refText: nil, createdAt: "", category: "场景",
            desc: "低柔气声，适合助眠、深夜节目"
        ),
        VoiceRecord(
            id: "preset.audiobook", name: "有声书讲述", kind: "preset", instruct:
                "有声书讲述者，中音，语气有叙事感，人物对话和叙述有细微区分，语速中等偏慢。",
            refAudio: nil, refText: nil, createdAt: "", category: "场景",
            desc: "有叙事起伏，适合长篇有声书"
        ),
        VoiceRecord(
            id: "preset.ad", name: "广告口播", kind: "preset", instruct:
                "广告口播，中高音，声音明亮有冲击力，语速快，重音清晰，句尾收得干脆。",
            refAudio: nil, refText: nil, createdAt: "", category: "场景",
            desc: "明亮有冲击力，适合广告、促销"
        ),
        VoiceRecord(
            id: "preset.assistant", name: "AI 助手", kind: "preset", instruct:
                "一个中性、清晰的 AI 助手声音，音色干净，语速稳定，语气礼貌但不机械。",
            refAudio: nil, refText: nil, createdAt: "", category: "场景",
            desc: "中性清晰，适合播报、提示音"
        )
    ]

    /// 模型自带的说话人槽位。实测 S0 约 78Hz、S2 约 120Hz、S5 约 145Hz、S9 约 107Hz，
    /// 含义未在模型文档中定义，所以只作为“高级”选项，按实测音高标注。
    static let speakers: [VoiceRecord] = [
        VoiceRecord(id: "speaker.S0", name: "S0 · 低男声", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "实测约 78 Hz"),
        VoiceRecord(id: "speaker.S1", name: "S1 · 内置槽位", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "未实测"),
        VoiceRecord(id: "speaker.S2", name: "S2 · 男中音", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "实测约 120 Hz"),
        VoiceRecord(id: "speaker.S3", name: "S3 · 内置槽位", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "未实测"),
        VoiceRecord(id: "speaker.S4", name: "S4 · 内置槽位", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "未实测"),
        VoiceRecord(id: "speaker.S5", name: "S5 · 女声", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "实测约 145 Hz"),
        VoiceRecord(id: "speaker.S6", name: "S6 · 内置槽位", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "未实测"),
        VoiceRecord(id: "speaker.S7", name: "S7 · 内置槽位", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "未实测"),
        VoiceRecord(id: "speaker.S8", name: "S8 · 内置槽位", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "未实测"),
        VoiceRecord(id: "speaker.S9", name: "S9 · 偏低男声", kind: "speaker", instruct: nil,
                    refAudio: nil, refText: nil, createdAt: "", category: "内置", desc: "实测约 107 Hz")
    ]
}

struct VoiceLibrary: Codable {
    var voices: [VoiceRecord]
}

/// 非 macOS 平台的可用形态，只做信息展示与命令复制，不参与本机下载。
struct CrossPlatformModel: Identifiable, Hashable {
    var id: String { repo + engine }
    let repo: String
    let title: String
    let engine: String
    let sizeText: String
    let note: String
    let command: String
    let recommended: Bool

    static let all: [CrossPlatformModel] = [
        CrossPlatformModel(
            repo: "BreezeBlue/Breeze-TTS-2",
            title: "官方 PyTorch 权重",
            engine: "Python + transformers / 官方 infer.py",
            sizeText: "7.68 GB",
            note: "Linux + NVIDIA 首选，eager 约 7.7 GB 显存；Windows 建议走 WSL2",
            command: "hf download BreezeBlue/Breeze-TTS-2 --local-dir breeze-tts-2",
            recommended: true
        ),
        CrossPlatformModel(
            repo: "HoppouAI/Breeze-TTS-2.cpp",
            title: "GGUF 量化（Q4_K / Q8_0 / F16）",
            engine: "llama.cpp / Breeze-TTS-2.cpp",
            sizeText: "2.5–6.3 GB",
            note: "Windows 无独显也能跑：Q4_K 最省，Q8_0 音质更好",
            command: "hf download HoppouAI/Breeze-TTS-2.cpp --include \"*q8_0.gguf\" --local-dir .",
            recommended: true
        ),
        CrossPlatformModel(
            repo: "drbaph/Breeze-TTS-2-comfyui",
            title: "ComfyUI 权重包",
            engine: "ComfyUI（ComfyUI-Breeze-TTS-2 节点）",
            sizeText: "约 5–7 GB",
            note: "推荐 int8-hybrid：接近 bf16 音质，显存省约 27%",
            command: "hf download drbaph/Breeze-TTS-2-comfyui --local-dir models/breeze",
            recommended: true
        ),
        CrossPlatformModel(
            repo: "smcleod/Breeze-TTS-2-int8",
            title: "PyTorch INT8",
            engine: "transformers（8 GB 级显存）",
            sizeText: "5.94 GB",
            note: "显存紧张的 CUDA 机器用这一版",
            command: "hf download smcleod/Breeze-TTS-2-int8 --local-dir breeze-int8",
            recommended: false
        ),
        CrossPlatformModel(
            repo: "cstr/breeze-tts-2-GGUF",
            title: "GGUF 备选",
            engine: "llama.cpp",
            sizeText: "2.2–5.7 GB",
            note: "另一个 GGUF 转换，q4_k 只有 2.2 GB",
            command: "hf download cstr/breeze-tts-2-GGUF --include \"*q4_k.gguf\" --local-dir .",
            recommended: false
        )
    ]
}
