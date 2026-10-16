import SwiftUI

// MARK: - Stimmungssuche

struct MoodSearchView: View {
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var result: MoodResult?
    @State private var searching = false
    @FocusState private var fieldFocused: Bool
    @Environment(HeroCoordinator.self) private var hero

    private let suggestions = [
        "Was Lustiges unter 2 Stunden",
        "Düster und spannend",
        "Filmabend mit Kindern",
        "Etwas wie Interstellar",
        "Romantisch, aber nicht kitschig",
        "Gruselig, mit Twist",
        "Bildgewaltig und episch",
        "Gemütlicher Sonntag"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchField
                    Label(MoodSearch.availabilityNote, systemImage: MoodSearch.isAppleIntelligenceAvailable ? "apple.intelligence" : "text.magnifyingglass")
                        .font(.caption).foregroundStyle(.secondary)

                    if searching {
                        HStack { Spacer(); ProgressView("Verstehe deinen Wunsch …"); Spacer() }.padding(.top, 40)
                    } else if let result {
                        results(result)
                    } else {
                        suggestionGrid
                    }
                }
                .padding(20)
            }
            .navigationTitle("Suche")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: text) { _, new in if new.isEmpty { withAnimation { result = nil } } }
            .task {
                if let q = UserDefaults.standard.string(forKey: "moodQuery"), result == nil { text = q; run(q) }
            }
            .background(BlurredBackdrop(film: result?.films.first?.film))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: MoodSearch.isAppleIntelligenceAvailable ? "apple.intelligence" : "magnifyingglass")
                .font(.title3)
                .foregroundStyle(MoodSearch.isAppleIntelligenceAvailable
                                 ? AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                 : AnyShapeStyle(.secondary))
                .symbolEffect(.pulse, isActive: searching)
            TextField("Stimmung, Thema, Titel …", text: $text)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { run(text) }
            if !text.isEmpty {
                Button {
                    withAnimation(.snappy) { text = ""; result = nil }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.body)
        .padding(.horizontal, 16).frame(height: 54)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.snappy, value: text.isEmpty)
    }

    private var suggestionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zum Beispiel").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestions, id: \.self) { s in
                    Button { text = s; fieldFocused = false; run(s) } label: {
                        Text(s).font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                }
            }
            Text("Die Suche versteht Stimmungen statt nur Titel. Mit Apple Intelligence läuft das komplett auf deinem Gerät, deine Anfrage verlässt das iPhone nicht.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    @ViewBuilder private func results(_ r: MoodResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Verstanden").font(.headline)
                if r.usedAppleIntelligence {
                    Image(systemName: "apple.intelligence").foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !r.query.summary.isEmpty {
                Text("„\(r.query.summary)“").font(.subheadline.italic()).foregroundStyle(.secondary)
            }
            FlowChips(items: understoodChips(r.query))
        }

        if let top = r.films.first {
            Button { hero.show(top.film, from: "search-top") } label: {
                RecommendationCard(rec: top, heroScope: "search-top")
                    .frame(maxWidth: 360).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            Text("Weitere Treffer").font(.headline).padding(.top, 6)
            ForEach(Array(r.films.dropFirst().enumerated()), id: \.element.id) { i, rec in
                Button { hero.show(rec.film, from: "search") } label: {
                    FilmRow(rec: rec, heroScope: "search")
                }
                .buttonStyle(.plain)
                .scrollTransition(.animated) { view, phase in
                    view.opacity(phase.isIdentity ? 1 : 0.4).scaleEffect(phase.isIdentity ? 1 : 0.95)
                }
            }
        } else {
            ContentUnavailableView("Nichts Passendes", systemImage: "film.stack",
                                   description: Text("Versuch's mit einer anderen Stimmung."))
        }
    }

    private func understoodChips(_ q: MoodQuery) -> [String] {
        var chips = q.moods.map(\.moodLabel) + q.genres
        if q.maxRuntimeMinutes > 0 { chips.append("≤ \(q.maxRuntimeMinutes) Min.") }
        if q.familyFriendly { chips.append("Familie") }
        if !q.similarTo.isEmpty { chips.append("wie „\(q.similarTo)“") }
        chips += q.exclude.map { "ohne \($0)" }
        return chips.isEmpty ? ["Alles"] : chips
    }

    private func run(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        fieldFocused = false
        withAnimation(.smooth) { searching = true; result = nil }
        Task {
            let r = await MoodSearch.search(query, profiles: store.activeProfiles)
            withAnimation(.smooth) { result = r; searching = false }
        }
    }
}

struct FilmRow: View {
    let rec: Recommendation
    /// Bereich für den Morph zu den Details; dann fliegt das kleine Cover groß auf.
    var heroScope: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let heroScope {
                    PosterView(film: rec.film, cornerRadius: 10).frame(width: 64)
                        .heroSource(rec.film, in: heroScope, cornerRadius: 10)
                } else {
                    PosterView(film: rec.film, cornerRadius: 10).frame(width: 64)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.film.title).font(.headline).lineLimit(2)
                Text(rec.film.metaLine).font(.caption).foregroundStyle(.secondary)
                ScoreBadges(film: rec.film, compact: true)
                Text(rec.reason).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !rec.film.comingSoon { MatchBadge(match: rec.match) }
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 18))
    }
}

// MARK: - Katalog (bewusst nur Nebenweg)

struct CatalogView: View {
    @Environment(AppStore.self) private var store
    @State private var genre: String?
    @State private var kind = 0
    @Environment(HeroCoordinator.self) private var hero

    private var maxFSK: Int { store.activeProfiles.map(\.maxFSK).min() ?? 18 }
    private func allowed(_ film: Film) -> Bool { store.activeProfiles.allSatisfy { $0.allows(film) } }

    var body: some View {
        let films = FilmIndex.all.filter {
            allowed($0) && !$0.comingSoon && (genre == nil || $0.genres.contains(genre!))
                && (kind == 0 || (kind == 2) == $0.isSeries)
        }
        let soon = FilmIndex.all.filter { $0.comingSoon && allowed($0) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Art", selection: $kind.animation(.smooth)) {
                        Text("Alles").tag(0)
                        Text("Filme").tag(1)
                        Text("Serien").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if !soon.isEmpty && genre == nil && kind != 2 {
                        Text("Demnächst").font(.title3.weight(.bold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(soon) { film in
                                    Button { hero.show(film, from: "catalog-soon") } label: {
                                        PosterView(film: film, cornerRadius: 14).frame(width: 150)
                                            .heroSource(film, in: "catalog-soon", cornerRadius: 14)
                                    }
                                    .buttonStyle(.plain)
                                    .scrollTransition(axis: .horizontal) { view, phase in
                                        view.scaleEffect(phase.isIdentity ? 1 : 0.9).rotation3DEffect(.degrees(phase.value * -12), axis: (0, 1, 0))
                                    }
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(nil, "Alle")
                            ForEach(FilmIndex.allGenres, id: \.self) { chip($0, $0) }
                        }
                    }
                    .scrollClipDisabled()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 14) {
                        ForEach(films) { film in
                            Button { hero.show(film, from: "catalog") } label: {
                                PosterView(film: film, cornerRadius: 12)
                                    .heroSource(film, in: "catalog", cornerRadius: 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("catalog.poster.\(film.id)")
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    if store.activeProfiles.contains(where: \.littleKid) {
                        Label("Nur Titel für kleine Kinder", systemImage: "shield.lefthalf.filled")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if maxFSK < 18 {
                        Label("Gefiltert bis FSK \(maxFSK)", systemImage: "shield.lefthalf.filled")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Katalog")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @Namespace private var chipNS

    private func chip(_ value: String?, _ label: String) -> some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { genre = value } } label: {
            Text(label).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(genre == value ? .black : .white)
                .background {
                    if genre == value {
                        Capsule().fill(.white).matchedGeometryEffect(id: "chip", in: chipNS)
                    } else {
                        Capsule().fill(.white.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: genre)
    }
}

// MARK: - Merkliste

struct WatchlistView: View {
    @Environment(AppStore.self) private var store
    @Environment(HeroCoordinator.self) private var hero

    var body: some View {
        NavigationStack {
            Group {
                if store.watchlist.isEmpty && store.continueWatching.isEmpty {
                    ContentUnavailableView {
                        Label("Noch nichts gemerkt", systemImage: "bookmark")
                    } description: {
                        Text("Wisch auf „Für dich“ einen Titel nach rechts, um ihn für später zu merken.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !store.continueWatching.isEmpty {
                                Text("Weiterschauen").font(.title3.weight(.bold))
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(store.continueWatching, id: \.film.id) { item in
                                            Button { hero.show(item.film, from: "continue") } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    PosterView(film: item.film, cornerRadius: 12, showsBadge: false)
                                                        .frame(width: 120)
                                                        .heroSource(item.film, in: "continue", cornerRadius: 12)
                                                    Text(item.film.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                    Text("Weiter mit \(item.next.short)").font(.caption).foregroundStyle(store.accent)
                                                }
                                                .frame(width: 120, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .scrollClipDisabled()
                                if !store.watchlist.isEmpty {
                                    Text("Gemerkt").font(.title3.weight(.bold)).padding(.top, 10)
                                }
                            }
                            ForEach(store.watchlist) { film in
                                Button { hero.show(film, from: "watchlist") } label: {
                                    FilmRow(rec: store.recommendation(for: film), heroScope: "watchlist")
                                }
                                    .buttonStyle(.plain)
                                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                                    .contextMenu {
                                        Button("Entfernen", systemImage: "trash", role: .destructive) { withAnimation(.snappy) { store.toggleWatchlist(film) } }
                                    }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Liste")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.watchlist.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(store.watchlist.count == 1 ? "1 Titel" : "\(store.watchlist.count) Titel")
                            .font(.subheadline.weight(.semibold))
                            .contentTransition(.numericText(value: Double(store.watchlist.count)))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }
}

// MARK: - Profil

struct ProfileTabView: View {
    @Environment(AppStore.self) private var store
    @State private var addingProfile = false
    @State private var showAccount = DemoScreen.current == "account"
    @State private var confirmReset = false
    @State private var aiSentences: [UUID: String] = [:]
    @State private var refining: UUID?
    @State private var chatting: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(store.activeProfiles) { profile in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                AvatarView(profile: profile, size: 44)
                                VStack(alignment: .leading) {
                                    Text(profile.name).font(.title2.weight(.bold))
                                    Text(profile.ageLabel)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            let ai = aiSentences[profile.id] ?? TasteWriter.cached(for: profile)
                            TasteCard(profile: profile, sentence: ai, usedAI: ai != nil)
                            HStack(spacing: 10) {
                                Button { refining = profile.id } label: {
                                    Label("Weiter swipen", systemImage: "rectangle.stack.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                Button { chatting = profile.id } label: {
                                    Label("KI beibringen", systemImage: MoodSearch.isAppleIntelligenceAvailable ? "apple.intelligence" : "bubble.left.and.text.bubble.right")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            if !profile.reviews.isEmpty {
                                Text("Bewertungen").font(.headline).padding(.top, 4)
                                ForEach(profile.reviews.prefix(5), id: \.self) { review in
                                    if let film = FilmIndex.film(review.filmID) {
                                        HStack(alignment: .top, spacing: 12) {
                                            PosterView(film: film, cornerRadius: 6).frame(width: 36)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(film.title).font(.subheadline.weight(.semibold))
                                                Text(ratingText(review.rating)).font(.caption).foregroundStyle(.secondary)
                                                if !review.text.isEmpty { Text(review.text).font(.caption).italic() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        NavigationLink { AccountView() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "gearshape").frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Einstellungen")
                                    if let sub = store.subscription {
                                        Text("\(sub.plan.name) · \(sub.statusText)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 50)
                        row("Profil hinzufügen", "person.badge.plus") { addingProfile = true }
                        Divider().padding(.leading, 50)
                        row("Demo zurücksetzen", "arrow.counterclockwise", role: .destructive) { confirmReset = true }
                    }
                    .glassEffect(in: .rect(cornerRadius: 22))

                }
                .padding(20)
            }
            .navigationDestination(isPresented: $showAccount) { AccountView() }
            .navigationTitle("Profil")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: store.activeProfileIDs) {
                if DemoScreen.current == "chat" { chatting = store.activeProfiles.first?.id }
                // Nur neu schreiben lassen, wenn sich die Geschmacksdaten geändert haben.
                for p in store.activeProfiles where TasteWriter.cached(for: p) == nil {
                    let (s, ai) = await TasteWriter.sentence(for: p)
                    if ai { withAnimation(.smooth(duration: 0.6)) { aiSentences[p.id] = s } }
                }
            }
        }
        .fullScreenCover(item: Binding(get: { refining.map(IdentifiedUUID.init) }, set: { refining = $0?.id })) { item in
            ZStack {
                Color.black.ignoresSafeArea()
                CalibrationStep(profileID: item.id, title: "Weiter verfeinern", minimum: 0) { refining = nil }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: Binding(get: { chatting.map(IdentifiedUUID.init) }, set: { chatting = $0?.id })) { item in
            TasteChatView(profileID: item.id)
        }
        .fullScreenCover(isPresented: $addingProfile) {
            OnboardingFlow(mode: .addProfile, cancel: { addingProfile = false }) { _ in addingProfile = false }
        }
        .confirmationDialog("Alle Profile und Bewertungen löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { store.resetAll() }
        }
    }

    private func ratingText(_ r: Interaction) -> String {
        switch r {
        case .ratedLove: "♥ Liebe ich"
        case .ratedUp: "👍 Gut"
        case .ratedOkay: "Okay"
        case .ratedDown: "👎 Schlecht"
        default: ""
        }
    }

    private func row(_ title: String, _ icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 22)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .primary)
    }
}

/// Kleiner Wrapper, damit eine UUID als `item` für Sheets dienen kann.
struct IdentifiedUUID: Identifiable { let id: UUID }
