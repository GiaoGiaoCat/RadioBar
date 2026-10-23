import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    // Preserve existing stored values when adding a language.
    case system, chinese, traditionalChinese, english
    var id: String { rawValue }
    static let preferenceKey = "appLanguage"

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        let parts = (preferredLanguages.first ?? "").lowercased()
            .replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard parts.first == "zh" else { return .english }
        // An explicit script takes precedence over the region (e.g. zh-Hans-HK).
        if parts.contains("hant") { return .traditionalChinese }
        if parts.contains("hans") { return .chinese }
        return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? .traditionalChinese : .chinese
    }

    func usesChinese(preferredLanguages: [String] = Locale.preferredLanguages) -> Bool {
        resolved(preferredLanguages: preferredLanguages) != .english
    }
}

/// Keep source text in memory so switching languages never restarts playback.
/// The native Hans-Hant transform provides generic Traditional Chinese, without
/// imposing Taiwan- or Hong Kong-specific vocabulary on station names/history.
struct RadioText: Equatable, Codable {
    let zh: String
    let en: String
    init(_ zh: String, _ en: String) { self.zh = zh; self.en = en }
    func value(_ language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch language.resolved(preferredLanguages: preferredLanguages) {
        case .traditionalChinese: return zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh
        case .chinese: return zh
        case .english, .system: return en
        }
    }
}

extension Station {
    var menuName: RadioText { title }
    var listeningStyle: RadioText { category }
    var displayName: RadioText {
        let full = fullName ?? title
        return RadioText(full.zh + (frequencyLabel.isEmpty ? "" : " " + frequencyLabel),
                         full.en + (frequencyLabel.isEmpty ? "" : " " + frequencyLabel))
    }
    var resolutionText: RadioText { resolutionText(attempt: 0) }
    func sourceText(attempt: Int) -> RadioText {
        guard let index = sourceIndex(attempt: attempt) else { return RadioText("无可用线路", "No available stream") }
        return index == 0 ? RadioText("主线路", "Primary stream") : RadioText("备用线路", "Backup stream")
    }
    func resolutionText(attempt: Int) -> RadioText {
        let source = sourceText(attempt: attempt)
        return RadioText("正在连接\(menuName.zh)\(source.zh)", "Connecting to \(menuName.en) · \(source.en)")
    }
}

extension RadioError {
    var displayText: RadioText {
        let english: String
        switch self {
        case .invalidResponse: english = "The station has no available stream address"
        case .timeout: english = "Connection or buffering timed out. Check your network and retry"
        case .playback: english = "The live stream failed. Retry or choose another station"
        }
        return RadioText(errorDescription ?? "连接失败", english)
    }
}

extension Error {
    /// Do not expose NSError userInfo, which can contain signed stream URLs.
    var radioDisplayText: RadioText {
        if let error = self as? RadioError { return error.displayText }
        return RadioText("网络请求失败，请检查网络后重试", "The network request failed. Check your connection and retry")
    }
}
