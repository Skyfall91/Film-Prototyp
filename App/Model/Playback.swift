@preconcurrency import AVKit
@preconcurrency import YouTubeKit
import Foundation

struct PlaybackRequest: Identifiable, Hashable {
    let id = UUID()
    let film: Film
    var trailer: Trailer? = nil
    /// Serien: welche Folge (im Prototyp läuft stellvertretend der Trailer).
    var episode: EpisodeRef? = nil
    /// „Abspielen“ zählt als gesehen (danach Bewertung), „Trailer“ nicht.
    var countsAsWatched: Bool
    var sourceID: String

    var videoID: String { trailer?.id ?? film.youtubeID }
}

enum TrailerLoader {
    static func playerItem(for request: PlaybackRequest) async throws -> AVPlayerItem {
        let youtube = YouTube(videoID: request.videoID, methods: [.local, .remote])

        // 1. HLS: das Format, für das AVPlayer gebaut ist, adaptive Qualität, sauberes Puffern.
        if let hls = try? await youtube.livestreams.first(where: { $0.streamType == .hls }) {
            let item = AVPlayerItem(url: hls.url)
            item.preferredForwardBufferDuration = 8
            return decorate(item, request)
        }

        let streams = try await youtube.streams.filter { $0.isNativelyPlayable }

        // 2. Getrennte Video- (bis 1080p) und Tonspur, zusammengesetzt.
        if let video = streams.filterVideoOnly().filter({ $0.fileExtension == .mp4 })
                .filter(byResolution: { ($0 ?? 0) <= 1080 }).highestResolutionStream(),
           let audio = streams.filterAudioOnly().filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream(),
           let composed = try? await playbackWithTimeout(seconds: 8, { PlaybackUnchecked(value: try await compose(video: video.url, audio: audio.url)) }) {
            return decorate(AVPlayerItem(asset: composed.value), request)
        }

        // 3. Fallback: kombinierter Stream.
        guard let combined = streams.filterVideoAndAudio().highestResolutionStream() else {
            throw URLError(.resourceUnavailable)
        }
        return decorate(AVPlayerItem(url: combined.url), request)
    }

    private static func compose(video: URL, audio: URL) async throws -> AVComposition {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        async let vTracks = videoAsset.loadTracks(withMediaType: .video)
        async let aTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let vDuration = videoAsset.load(.duration)
        async let aDuration = audioAsset.load(.duration)
        guard let vTrack = try await vTracks.first, let aTrack = try await aTracks.first else {
            throw URLError(.cannotParseResponse)
        }
        let duration = try await min(vDuration, aDuration)
        let range = CMTimeRange(start: .zero, duration: duration)
        let composition = AVMutableComposition()
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: vTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: aTrack, at: .zero)
        return composition
    }

    /// Titel, Beschreibung und Poster für die Info-Leiste des Systemplayers.
    private static func decorate(_ item: AVPlayerItem, _ request: PlaybackRequest) -> AVPlayerItem {
        let film = request.film
        func meta(_ id: AVMetadataIdentifier, _ value: any NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value
            m.extendedLanguageTag = "und"
            return m
        }
        let subtitle = (request.trailer.map { "\($0.title) · " } ?? "") + film.metaLine
        var items = [meta(.commonIdentifierTitle, film.title as NSString),
                     meta(.commonIdentifierDescription, film.synopsis as NSString),
                     meta(.iTunesMetadataTrackSubTitle, subtitle as NSString)]
        if let data = film.posterImage?.jpegData(compressionQuality: 0.8) {
            items.append(meta(.commonIdentifierArtwork, data as NSData))
        }
        item.externalMetadata = items
        return item
    }
}

/// Verpackt nicht-Sendable AVFoundation-Objekte für den Timeout-Wettlauf.
nonisolated struct PlaybackUnchecked<T>: @unchecked Sendable { let value: T }

nonisolated func playbackWithTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
