import Foundation

struct StreamAddress {
    let url: URL
}

enum RadioError: LocalizedError {
    case invalidResponse, timeout, playback
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "电台没有可用的播放地址"
        case .timeout: return "连接或缓冲超时，请检查网络后重试"
        case .playback: return "直播连接失败，请重试或切换电台"
        }
    }
}

/// Keep source rotation independent of the retry budget: healthy playback resets
/// the budget without losing track of which source is currently in use.
struct PlaybackRecovery {
    private(set) var retryCount = 0
    private(set) var sourceAttempt = 0

    mutating func recordHealthyPlayback() { retryCount = 0 }

    mutating func retryAfterFailure() -> Int? {
        guard retryCount < 4 else { return nil }
        retryCount += 1
        sourceAttempt += 1
        return 1 << retryCount
    }
}

protocol StreamURLResolving {
    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress
}

/// Selection is local and uses the immutable station snapshot supplied by the player.
struct StreamResolver: StreamURLResolving {
    static func directURLs(for station: Station) -> [URL] { station.urls }

    func resolve(_ station: Station, attempt: Int) async throws -> StreamAddress {
        try Task.checkCancellation()
        guard let index = station.sourceIndex(attempt: attempt) else { throw RadioError.invalidResponse }
        return StreamAddress(url: station.urls[index])
    }
}
