import AppKit
import SwiftUI

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading
        case downloaded(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releasePage: URL?
    @Published private(set) var notes: String?

    private let repo = "m0ba/BreezeLocal"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 先用 releases/latest 的跳转拿版本号（快且不需要 API 配额），再后台补更新说明。
    func check() {
        guard state != .checking else { return }
        state = .checking
        Task {
            do {
                let version = try await fetchViaRedirect()
                latestVersion = version
                releasePage = URL(string: "https://github.com/\(repo)/releases/tag/v\(version)")
                state = Self.isNewer(version, than: currentVersion) ? .available(version) : .upToDate
                if let info = try? await fetchViaAPI() {
                    notes = info.body
                    releasePage = URL(string: info.htmlUrl) ?? releasePage
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private struct APIRelease: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    private func fetchViaAPI() async throws -> APIRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BreezeLocal/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(APIRelease.self, from: data)
    }

    private func fetchViaRedirect() async throws -> String {
        var request = URLRequest(url: URL(string: "https://github.com/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("BreezeLocal/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let finalURL = response.url,
              finalURL.pathComponents.count >= 2 else {
            throw URLError(.badServerResponse)
        }
        let tag = finalURL.lastPathComponent
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.first?.isNumber == true else { throw URLError(.cannotParseResponse) }
        return version
    }

    var dmgURL: URL? {
        guard let latestVersion else { return nil }
        return URL(string: "https://github.com/\(repo)/releases/download/v\(latestVersion)/BreezeLocal-\(latestVersion).dmg")
    }

    func downloadAndOpen() {
        guard let url = dmgURL else {
            if let releasePage { NSWorkspace.shared.open(releasePage) }
            return
        }
        state = .downloading
        Task {
            do {
                let (temp, response) = try await URLSession.shared.download(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NSError(domain: "BreezeLocal", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "下载失败：HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                    ])
                }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let target = downloads.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: temp, to: target)
                state = .downloaded(target.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasePage() {
        if let releasePage { NSWorkspace.shared.open(releasePage) }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
