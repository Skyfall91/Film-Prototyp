import SwiftUI

// MARK: - Details

struct FilmDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var playing: PlaybackRequest?
    @Namespace private var playerNS
    @Environment(\.dismiss) private var dismiss
    let film: Film
    @State private var shownMatch = 0
    @State private var aiTeaser: String?
    @State private var bookmarkBounce = 0
    @State private var sharePlay = false
    /// Morph von „Für dich“: Das Cover fliegt als eigene Ebene herein (`HeroOverlay`), solange
    /// bleibt das echte Cover hier unsichtbar und liefert nur die Zielposition.
    var posterHidden = false
    /// Nur wenn der Titel von einer Karte mitfliegt.
    var contentVisible = true
    var onClose: (() -> Void)? = nil
    var onPosterFrame: ((CGRect) -> Void)? = nil
    static let titleFont = Theme.filmTitle(size: 34)
    @State private var closing = false
    /// Vom linken Rand wischen: Die Seite schrumpft unter dem Finger und fliegt dann zurück.
    @State private var edgeDrag: CGFloat = 0

    var body: some View {
        let rec = store.recommendation(for: film)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero(rec)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !film.synopsis.isEmpty {
                            Text(film.synopsis).font(.body)
                        } else if let aiTeaser {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(aiTeaser).font(.body)
                                Label("Anreißer von Apple Intelligence", systemImage: "apple.intelligence")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .transition(.opacity)
                        }
                    }
                    if let voices = film.voices, !voices.isEmpty {
                        editorial(voices)
                    }
                    if film.isSeries {
                        EpisodeList(film: film) { ref in
                            playing = PlaybackRequest(film: film, episode: ref, countsAsWatched: true, sourceID: film.id)
                        }
                    }
                    if film.trailers.count > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Trailer").font(.title3.weight(.bold))
                                Text("\(film.trailers.count)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            TrailerPicker(film: film, namespace: playerNS) { trailer in
                                playing = PlaybackRequest(film: film, trailer: trailer, countsAsWatched: false, sourceID: trailer.id)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        credit(film.isSeries ? "Idee" : "Regie", film.director)
                        credit("Mit", film.cast.joined(separator: ", "))
                    }
                    .font(.subheadline)
                    Link(destination: URL(string: "https://letterboxd.com/imdb/\(film.imdbID)/")!) {
                        Label("Auf Letterboxd ansehen", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        // Nach unten ziehen schließt, wie bei einem Sheet.
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            guard let onClose, !closing, y < -90 else { return }
            closing = true
            onClose()
        }
        .scaleEffect(1 - edgeProgress * 0.14, anchor: .center)
        .offset(x: edgeDrag * 0.35)
        .opacity(contentVisible ? 1 : 0)
        .background(BlurredBackdrop(film: film).opacity(contentVisible ? 1 - edgeProgress * 0.35 : 0))
        // Beim Schließen schnell weg, damit Match und Einzeiler der Karte schon während des Flugs da sind.
        .animation(contentVisible ? .easeOut(duration: 0.35) : .easeOut(duration: 0.18), value: contentVisible)
        .simultaneousGesture(edgeSwipe, isEnabled: onClose != nil && !closing)
        // Apples Schließen-Button, ohne Navigationsleiste: Die würde die Flug-Ebene verschieben.
        .overlay(alignment: .topTrailing) {
            if let onClose {
                // Gleiche Größe wie Rückgängig und Filter: 44 pt Glaskreis.
                Button(role: .close) { closing = true; onClose() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.white)
                .accessibilityLabel("Schließen")
                    .padding(.trailing, 16).padding(.top, 4)
                    .opacity(contentVisible ? 1 : 0)
            }
        }
        .filmPlayer($playing, in: playerNS)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.smooth(duration: 0.9)) { shownMatch = rec.match }
            if film.synopsis.isEmpty, let t = await SynopsisWriter.teaser(for: film) {
                withAnimation(.smooth) { aiTeaser = t }
            }
        }
    }

    private var edgeProgress: CGFloat { min(max(edgeDrag, 0) / 320, 1) }

    /// Zurück wie in jeder iOS-App: am linken Rand ansetzen und nach rechts ziehen.
    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard value.startLocation.x < 44, value.translation.width > abs(value.translation.height) * 0.6 || edgeDrag > 0 else { return }
                edgeDrag = max(value.translation.width, 0)
            }
            .onEnded { value in
                guard edgeDrag > 0 else { return }
                if edgeDrag > 110 || value.predictedEndTranslation.width > 260 {
                    closing = true
                    onClose?()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { edgeDrag = 0 }
                }
            }
    }

    /// Das Cover ist die Lichtquelle der Seite: groß in der Mitte, sein eigener Schein fällt in den Raum.
    /// Darunter die Kritiken mit den Zeichen ihrer Quellen, dann Titel und Entscheidung.
    /// Das Cover ist die Bühne: randlos über die ganze Breite, bis unter die Statusleiste.
    /// Unten läuft es ins Dunkle aus, Titel und Fakten liegen darauf wie auf einem Kinoplakat.
    /// Darunter nur noch, was zur Entscheidung führt: Kritiken, warum es passt, Abspielen.
    private func hero(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterView(film: film, cornerRadius: 0, showsBadge: false)
                .matchedTransitionSource(id: film.id, in: playerNS)
                .containerRelativeFrame(.horizontal)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onPosterFrame?($0) }
                .opacity(posterHidden ? 0 : 1)
                // Der Verlauf gehört zur Seite, nicht zum Cover: Er blendet mit dem Inhalt ein,
                // das fliegende Cover landet ohne Sprung.
                .overlay {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                        Spacer()
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black.opacity(0.7), location: 0.45),
                                               .init(color: .black, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 300)
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) { titleBlock.padding(.horizontal, 20).padding(.bottom, 18) }

            VStack(alignment: .leading, spacing: 0) {
                laurels

                if !film.comingSoon {
                    HStack(spacing: 10) {
                        MatchRing(match: shownMatch, target: rec.match, size: 30)
                        Text(rec.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 14)
                }

                actions
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            // Das Schwarz unter dem Cover läuft weich in den Hintergrund der Seite aus, ohne Kante.
            .background(alignment: .top) {
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
                    .allowsHitTesting(false)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(film.title)
                .font(Self.titleFont)
                .foregroundStyle(.white)
                .lineLimit(3).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 2)
            HStack(spacing: 6) {
                Text(film.isSeries ? "Serie" : "Film")
                Text("·")
                Text(film.yearText)
                Text("·")
                Text(film.isSeries ? film.seasonsText : film.runtimeText)
                FSKBadge(fsk: film.fsk)
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.8))
            if film.comingSoon {
                Text(film.releaseNote ?? "Demnächst")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            if film.originalTitle != film.title, !film.title.hasPrefix(film.originalTitle) {
                Text(film.originalTitle).font(.footnote).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Die Redaktion wie auf einem Kinoplakat zur Award-Saison: das Cover als Bühne,
    /// rechts darauf fett der Blickwinkel, darunter der Satz.
    private func editorial(_ voices: [Film.Voice]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Die Redaktion meint").font(.title3.weight(.bold))
            VStack(alignment: .trailing, spacing: 16) {
                ForEach(voices, id: \.self) { v in
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(v.label):")
                            .font(.subheadline.weight(.bold))
                        Text("„\(v.text)“")
                            .font(.system(size: 18, design: .serif))
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 22).padding(.trailing, 20).padding(.leading, 70)
            .background {
                // Das Cover füllt die ganze Fläche, wie das Foto auf einem Kinoplakat.
                Color(white: 0.12)
                    .overlay {
                        if let image = film.posterImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.88)],
                                            startPoint: .leading, endPoint: .trailing))
            }
            .clipShape(.rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            HStack(spacing: 4) {
                Text("Ausgewählt von unserer Redaktion ·")
                Link("Kritiken lesen", destination: URL(string: "https://www.rottentomatoes.com/search?search=\(query)")!)
                    .fontWeight(.semibold)
            }
            .font(.caption).foregroundStyle(.secondary).tint(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    /// Kritiken als eine ruhige Reihe: Zeichen der Quelle und Zahl, Antippen öffnet die Quelle.
    private var laurels: some View {
        HStack(spacing: 18) {
            if let imdb = film.imdbRating {
                let value = imdb.formatted(.number.precision(.fractionLength(1)))
                score(source: "IMDb", spoken: value, url: "https://www.imdb.com/title/\(film.imdbID)/") {
                    Text("IMDb")
                        .font(.system(size: 11, weight: .black)).foregroundStyle(.black)
                        .padding(.horizontal, 5).frame(height: 20)
                        .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: .rect(cornerRadius: 4))
                    Text(value)
                }
            }
            if let rt = film.rottenTomatoes {
                score(source: "Rotten Tomatoes", spoken: "\(rt) Prozent", url: "https://www.rottentomatoes.com/search?search=\(query)") {
                    Text(rt >= 60 ? "🍅" : "🤢").font(.system(size: 16))
                    Text("\(rt) %")
                }
            }
            if let mc = film.metascore {
                score(source: "Metacritic", spoken: "\(mc)", url: "https://www.metacritic.com/search/\(query)/") {
                    Text("\(mc)")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 26, height: 20)
                        .background(mc >= 61 ? Color(red: 0.4, green: 0.8, blue: 0.2) : mc >= 40 ? Color(red: 0.95, green: 0.75, blue: 0.1) : .red,
                                    in: .rect(cornerRadius: 4))
                    Text("Metascore").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func score<Mark: View>(source: String, spoken: String, url: String, @ViewBuilder mark: () -> Mark) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) { mark() }
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(source): \(spoken)")
        .accessibilityHint("Öffnet die Quelle")
    }

    private var query: String {
        film.originalTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? film.originalTitle
    }

    /// Zwei Ebenen statt einer gequetschten Zeile: oben die eine Hauptaktion in voller Breite
    /// (bei Serien mit der Folge darunter), darunter Trailer und Merken gleich breit.
    private var actions: some View {
        VStack(spacing: 10) {
            if !film.comingSoon {
                Button {
                    playing = PlaybackRequest(film: film, episode: store.upNext(film), countsAsWatched: true, sourceID: film.id)
                } label: {
                    VStack(spacing: 1) {
                        Label(playTitle, systemImage: "play.fill").font(.headline)
                        if let subtitle = playSubtitle {
                            Text(subtitle).font(.caption.weight(.medium)).opacity(0.7).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(store.accent).interactive(), in: .capsule)
            }
            HStack(spacing: 10) {
                Button {
                    playing = PlaybackRequest(film: film, trailer: film.trailers.first, countsAsWatched: false, sourceID: film.id)
                } label: {
                    Label("Trailer", systemImage: "film")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(film.trailers.isEmpty)
                Button {
                    withAnimation(.snappy) { store.toggleWatchlist(film) }
                    bookmarkBounce += 1
                } label: {
                    // Platz für das längste Wort reservieren, sonst springt das Symbol,
                    // wenn „Merken“ zu „Gemerkt“ wird.
                    HStack(spacing: 6) {
                        Image(systemName: store.isOnWatchlist(film) ? "bookmark.fill" : "bookmark")
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: bookmarkBounce)
                        ZStack(alignment: .leading) {
                            Text(film.comingSoon ? "Erinnern" : "Gemerkt").hidden()
                            Text(store.isOnWatchlist(film) ? "Gemerkt" : (film.comingSoon ? "Erinnern" : "Merken"))
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .sensoryFeedback(.success, trigger: bookmarkBounce)
                if !film.comingSoon {
                    Button { sharePlay = true } label: {
                        Image(systemName: "shareplay")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Mit SharePlay schauen")
                }
            }
        }
        .sheet(isPresented: $sharePlay) { SharePlaySheet(film: film) }
    }

    private var playTitle: String {
        guard film.isSeries else { return "Abspielen" }
        return store.nextEpisode(of: film) == nil ? "Ansehen" : "Weiterschauen"
    }

    /// „Staffel 1 · Folge 4 · Lügen“, damit klar ist, was startet.
    private var playSubtitle: String? {
        guard let ref = store.upNext(film) else { return nil }
        let title = film.episode(ref).map { " · \($0.title)" } ?? ""
        return "Staffel \(ref.season) · Folge \(ref.episode)\(title)"
    }

    private func credit(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            Text(value)
        }
    }
}

/// Staffeln und Folgen. Die nächste Folge des Profils ist markiert; antippen spielt sie ab.
struct EpisodeList: View {
    @Environment(AppStore.self) private var store
    let film: Film
    var play: (EpisodeRef) -> Void
    @State private var season = 0

    var body: some View {
        let seasons = film.seasons ?? []
        let next = store.nextEpisode(of: film)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Folgen").font(.title3.weight(.bold))
                Spacer()
                if seasons.count > 1 {
                    Picker("Staffel", selection: $season) {
                        ForEach(seasons, id: \.number) { Text("Staffel \($0.number)").tag($0.number) }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
            }
            if let current = seasons.first(where: { $0.number == season }) {
                VStack(spacing: 0) {
                    ForEach(current.episodes, id: \.number) { ep in
                        let ref = EpisodeRef(season: current.number, episode: ep.number)
                        let isNext = ref == next
                        let watched = next.map { isBefore(ref, $0) } ?? false
                        Button { play(ref) } label: {
                            HStack(spacing: 14) {
                                Text("\(ep.number)")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(isNext ? store.accent : .secondary)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ep.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(isNext ? "Als Nächstes · \(film.runtimeText)" : watched ? "Gesehen" : film.runtimeText)
                                        .font(.caption)
                                        .foregroundStyle(isNext ? store.accent : .secondary)
                                }
                                Spacer()
                                Image(systemName: watched ? "checkmark.circle.fill" : "play.circle")
                                    .font(.title3)
                                    .foregroundStyle(watched ? Color.secondary : isNext ? store.accent : .primary)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(isNext ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 14))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Folge \(ep.number): \(ep.title)")
                    }
                }
                .padding(6)
                .glassEffect(in: .rect(cornerRadius: 22))
            }
            if (film.totalSeasons ?? 0) > seasons.count {
                Text("Im Prototyp sind die ersten \(seasons.count) von \(film.totalSeasons ?? 0) Staffeln hinterlegt.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear { season = next?.season ?? seasons.first?.number ?? 1 }
    }

    private func isBefore(_ a: EpisodeRef, _ b: EpisodeRef) -> Bool {
        a.season < b.season || (a.season == b.season && a.episode < b.episode)
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(items, id: \.self) { TagChip(text: $0) } }
                .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -20)
    }
}

extension Color {
    /// Akzentfarbe: Weiß wie in den Apple-Apps, Farbe kommt nur aus den Postern.
    static let highlight = Color.white
}

// MARK: - Bewertung nach dem Schauen

struct RatingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pending: PendingRating

    @State private var ratings: [UUID: Interaction] = [:]
    @State private var reviews: [UUID: String] = [:]
    @State private var writing: UUID?

    private let choices: [(Interaction, String, String, Color)] = [
        (.ratedDown, "Schlecht", "hand.thumbsdown.fill", Color(red: 1, green: 0.27, blue: 0.3)),
        (.ratedOkay, "Okay", "hand.raised.fill", .yellow),
        (.ratedUp, "Gut", "hand.thumbsup.fill", Color(red: 0.2, green: 0.85, blue: 0.5)),
        (.ratedLove, "Liebe ich", "heart.fill", Color(red: 1, green: 0.3, blue: 0.6))
    ]

    var body: some View {
        let film = FilmIndex.film(pending.filmID)
        let profiles = store.profiles.filter { pending.profileIDs.contains($0.id) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let film {
                        HStack(spacing: 16) {
                            PosterView(film: film, cornerRadius: 12).frame(width: 80)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profiles.count > 1 ? "Wie fandet ihr" : "Wie fandest du").foregroundStyle(.secondary)
                                Text(film.title).font(.title2.weight(.heavy))
                                Text("Jede Bewertung zählt nur für das eigene Profil.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    ForEach(profiles) { profile in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                AvatarView(profile: profile, size: 32)
                                Text(profile.name).font(.headline)
                                Spacer()
                                Button {
                                    withAnimation { writing = writing == profile.id ? nil : profile.id }
                                } label: {
                                    Label("Review", systemImage: "square.and.pencil").font(.subheadline)
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach(choices, id: \.0) { choice in
                                    let selected = ratings[profile.id] == choice.0
                                    Button {
                                        withAnimation(.snappy) { ratings[profile.id] = choice.0 }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: choice.2).font(.title2)
                                                .symbolEffect(.bounce, value: selected)
                                            Text(choice.1).font(.caption2.weight(.semibold))
                                        }
                                        .foregroundStyle(selected ? .white : choice.3)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(selected ? AnyShapeStyle(choice.3.gradient) : AnyShapeStyle(.white.opacity(0.06)),
                                                    in: .rect(cornerRadius: 16))
                                    }
                                    .buttonStyle(.plain)
                                    .sensoryFeedback(.selection, trigger: selected)
                                }
                            }
                            if writing == profile.id {
                                TextField("Was hat dir gefallen, oder nicht?", text: Binding(
                                    get: { reviews[profile.id] ?? "" }, set: { reviews[profile.id] = $0 }), axis: .vertical)
                                    .lineLimit(3...6)
                                    .padding(12)
                                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
                            }
                        }
                        .padding(16)
                        .glassEffect(in: .rect(cornerRadius: 24))
                    }
                }
                .padding(20)
            }
            .navigationTitle("Bewerten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Später") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        store.rate(pending, ratings: ratings, reviews: reviews)
                        dismiss()
                    }
                    .disabled(ratings.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - SharePlay (Prototyp)

/// Zusammen schauen über FaceTime. Im Prototyp nur angedeutet: Echtes SharePlay braucht eine
/// Berechtigung aus dem bezahlten Apple-Entwicklerprogramm. Mit ihr würde der Player per
/// GroupActivities und AVPlaybackCoordinator bei allen gleichzeitig laufen.
struct SharePlaySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let film: Film
    @State private var ready = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: ready ? "checkmark.circle.fill" : "shareplay")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(ready ? Color.green : store.accent)
                .contentTransition(.symbolEffect(.replace))
                .padding(.top, 28)
            VStack(spacing: 8) {
                Text(ready ? "Bereit für SharePlay" : "Zusammen schauen")
                    .font(.title2.weight(.bold))
                    .contentTransition(.opacity)
                Text(ready
                     ? "„\(film.title)“ startet bei allen, sobald ihr in einem FaceTime-Anruf seid."
                     : "Ruf jemanden per FaceTime an. „\(film.title)“ läuft dann bei allen gleichzeitig, Pause und Spulen gelten für alle.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 24)
            HStack(spacing: 14) {
                PosterView(film: film, cornerRadius: 8, showsBadge: false).frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(film.title).font(.headline).lineLimit(1)
                    Text("Alle brauchen ein eigenes Abo").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
            Button {
                if ready { dismiss() } else { withAnimation(.smooth) { ready = true } }
            } label: {
                Text(ready ? "Fertig" : "SharePlay starten")
                    .font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(store.accent).interactive(), in: .capsule)
            .padding(.horizontal, 24).padding(.bottom, 12)
            .sensoryFeedback(.success, trigger: ready)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
