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
        .background(BlurredBackdrop(film: film))
        .presentationDragIndicator(.visible)
        .filmPlayer($playing, in: playerNS)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.smooth(duration: 0.9)) { shownMatch = rec.match }
            if film.synopsis.isEmpty, let t = await SynopsisWriter.teaser(for: film) {
                withAnimation(.smooth) { aiTeaser = t }
            }
        }
    }

    /// Das Cover ist die Lichtquelle der Seite: groß in der Mitte, sein eigener Schein fällt in den Raum.
    /// Darunter die Kritiken wie Lorbeeren auf einem Kinoplakat, dann Titel und Entscheidung.
    private func hero(_ rec: Recommendation) -> some View {
        VStack(spacing: 0) {
            PosterView(film: film, cornerRadius: 14, showsBadge: false)
                .matchedTransitionSource(id: film.id, in: playerNS)
                .containerRelativeFrame(.horizontal) { w, _ in min(w * 0.62, 320) }
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
            .padding(.top, 36)

            laurels
                .padding(.top, 26)

            VStack(spacing: 10) {
                Label(film.isSeries ? "Serie · Folgen à \(film.runtimeText)" : "Film",
                      systemImage: film.isSeries ? "tv" : "film")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if film.comingSoon {
                    Text(film.releaseNote ?? "Demnächst")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(film.title)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    Text(film.yearText)
                    Text("·")
                    Text(film.isSeries ? film.seasonsText : film.runtimeText)
                    FSKBadge(fsk: film.fsk)
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if film.originalTitle != film.title, !film.title.hasPrefix(film.originalTitle) {
                    Text(film.originalTitle).font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            if !film.comingSoon {
                HStack(spacing: 10) {
                    MatchRing(match: shownMatch, target: rec.match, size: 34)
                    Text(rec.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.top, 18)
                .padding(.horizontal, 28)
            }

            actions
                .padding(.horizontal, 20)
                .padding(.top, 24)
        }
    }

    /// Kritiken im Vokabular des Kinoplakats: Lorbeerkranz, Zahl, Quelle. Antippen öffnet die Quelle.
    private var laurels: some View {
        HStack(alignment: .top, spacing: 22) {
            if let imdb = film.imdbRating {
                laurel(imdb.formatted(.number.precision(.fractionLength(1))), source: "IMDb",
                       url: "https://www.imdb.com/title/\(film.imdbID)/")
            }
            if let rt = film.rottenTomatoes {
                laurel("\(rt) %", source: "Kritiken",
                       url: "https://www.rottentomatoes.com/search?search=\(query)")
            }
            if let mc = film.metascore {
                laurel("\(mc)", source: "Metacritic", url: "https://www.metacritic.com/search/\(query)/")
            }
        }
    }

    private func laurel(_ value: String, source: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 2) {
                HStack(spacing: 1) {
                    Image(systemName: "laurel.leading")
                    Text(value)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .monospacedDigit()
                    Image(systemName: "laurel.trailing")
                }
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.primary.opacity(0.9))
                Text(source)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source): \(value)")
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
                    Label(store.isOnWatchlist(film) ? "Gemerkt" : (film.comingSoon ? "Erinnern" : "Merken"),
                          systemImage: store.isOnWatchlist(film) ? "bookmark.fill" : "bookmark")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: bookmarkBounce)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .sensoryFeedback(.success, trigger: bookmarkBounce)
                if !film.comingSoon {
                    Button { sharePlay = true } label: {
                        Image(systemName: "shareplay")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
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
