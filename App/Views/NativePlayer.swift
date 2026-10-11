@preconcurrency import AVKit
import MediaPlayer
import SwiftUI
@preconcurrency import YouTubeKit

/// Was abgespielt werden soll. `sourceID` ist die View, aus der der Player herausmorpht.
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

extension View {
    /// Vollbild-Player, der per Zoom-Übergang aus `sourceID` heraus aufgeht
    /// und sich nach unten wegwischen lässt.
    func filmPlayer(_ request: Binding<PlaybackRequest?>, in namespace: Namespace.ID) -> some View {
        fullScreenCover(item: request) { req in
            PlayerGate(request: req)
                .navigationTransition(.zoom(sourceID: req.sourceID, in: namespace))
        }
    }
}

/// Abspielen braucht ein aktives Abo – Trailer nicht. Ohne Abo erscheint statt des Players die Tarifwahl.
private struct PlayerGate: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    var body: some View {
        if request.countsAsWatched && !store.canPlay {
            PlanPicker(mode: .unlock) { _ in dismiss() }
        } else {
            PlayerScreen(request: request)
        }
    }
}

// MARK: - Player-Screen

/// Im Prototyp ist der Trailer der Film. Der YouTube-Trailer wird in eine direkte
/// Stream-URL aufgelöst und im nativen iOS-Player (AVPlayerViewController) gezeigt.
struct PlayerScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let request: PlaybackRequest

    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var showVideo = false
    @State private var closed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Platzhalter: das Poster füllt den Screen, solange der Stream lädt –
            // so wirkt der Zoom aus der Karte nahtlos.
            if !showVideo {
                ZStack {
                    if let image = request.film.posterImage {
                        Color.clear.overlay {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                        .clipped()
                        .overlay(Color.black.opacity(0.45))
                    }
                    VStack(spacing: 14) {
                        if failed {
                            Text("Der Film konnte gerade nicht geladen werden.").font(.headline)
                            Button {
                                openURL(URL(string: "https://www.youtube.com/watch?v=\(request.videoID)")!)
                            } label: { Label("Auf YouTube ansehen", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.glassProminent)
                        } else {
                            ProgressView().controlSize(.large).tint(.white)
                            Text(loadingTitle).font(.headline).multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding()
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            if let player {
                SystemPlayer(player: player)
                    .ignoresSafeArea()
                    .opacity(showVideo ? 1 : 0)
                // Unterdrückt das System-Lautstärke-Popup – der Player zeigt seine eigene Anzeige.
                SystemVolumeHUDSuppressor()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) {
            if !showVideo {
                Button { close() } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.leading, 16)
                .padding(.top, 8)
                .accessibilityLabel("Schließen")
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .task { await load() }
        // Film zu Ende → Player schließen, zurück ins Hochformat.
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            if (note.object as? AVPlayerItem) === player?.currentItem { close() }
        }
        .onDisappear {
            closed = true
            player?.pause()
            AppDelegate.allowLandscape = false
            PlayerOrientation.rotate(to: .portrait)
            if request.countsAsWatched {
                let before = store.pendingRatings.count
                store.play(request.film, episode: request.episode)
                // Erst drehen, dann bewerten – ein Sheet mitten in der Drehung hält sonst das Querformat fest.
                // Serien werden nur nach der ersten Folge bewertet.
                let pending = store.pendingRatings.count > before || !request.film.isSeries ? store.pendingRatings.last : nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    PlayerOrientation.rotate(to: .portrait)
                    store.ratingToPresent = pending
                }
            }
        }
    }

    private var loadingTitle: String {
        if let trailer = request.trailer { return trailer.title }
        if let ref = request.episode, let ep = request.film.episode(ref) {
            return "\(request.film.title)\n\(ref.short) · \(ep.title)"
        }
        return request.film.title
    }

    /// Schließen: zuerst ins Hochformat zurück, dann der Zoom zurück in die Karte.
    private func close() {
        guard !closed else { return }
        closed = true
        player?.pause()
        AppDelegate.allowLandscape = false
        PlayerOrientation.rotate(to: .portrait)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }

    private func load() async {
        do {
            let item = try await TrailerLoader.playerItem(for: request)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            player.play()
            withAnimation(.smooth(duration: 0.5)) { showVideo = true }
            // Wie bei Netflix: nach dem Aufzoomen ins Querformat drehen –
            // aber nicht mehr, wenn der Player in der Zwischenzeit geschlossen wurde.
            try? await Task.sleep(for: .milliseconds(250))
            guard !closed, !Task.isCancelled else { return }
            AppDelegate.allowLandscape = true
            PlayerOrientation.rotate(to: .landscapeRight)
        } catch {
            withAnimation { failed = true }
        }
    }
}

/// Der native iOS-Player, eingebettet in SwiftUI. Schließen per Wischen nach unten
/// (Zoom-Übergang) oder über die Systemsteuerung.
struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

/// Solange ein MPVolumeView sichtbar im Fenster liegt, blendet iOS sein eigenes
/// Lautstärke-Popup aus. So erscheint nur die Anzeige des Players.
struct SystemVolumeHUDSuppressor: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.showsVolumeSlider = true
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

enum PlayerOrientation {
    static func rotate(to mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        var vc = scene.keyWindow?.rootViewController
        while let current = vc {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

// MARK: - Stream auflösen

enum TrailerLoader {
    static func playerItem(for request: PlaybackRequest) async throws -> AVPlayerItem {
        let youtube = YouTube(videoID: request.videoID, methods: [.local, .remote])

        // 1. HLS: das Format, für das AVPlayer gebaut ist – adaptive Qualität, sauberes Puffern.
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
           let composed = try? await withTimeout(seconds: 8, { Unchecked(value: try await compose(video: video.url, audio: audio.url)) }) {
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
nonisolated private struct Unchecked<T>: @unchecked Sendable { let value: T }

nonisolated private func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
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
