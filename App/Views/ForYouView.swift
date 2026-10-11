import SwiftUI

/// Startseite: genau ein Vorschlag. Wischen statt Scrollen.
struct ForYouView: View {
    @Environment(AppStore.self) private var store
    @State private var playing: PlaybackRequest?
    @Namespace private var zoom
    @State private var trigger: SwipeDirection?
    @State private var detailFilm: Film?
    @State private var addingProfile = false
    @State private var toast: Toast?
    @State private var undoBounce = 0
    /// Feste Warteschlange: Was hinten im Stapel liegt, bleibt dort. Nach jedem Swipe
    /// wird nur hinten aufgefüllt, sonst würden Karten (und Hintergrund) durch das
    /// Nachlernen plötzlich ausgetauscht.
    @State private var queue: [Recommendation] = []
    @State private var swiped: [Recommendation] = []
    /// Geschmack hat sich geändert, während „Für dich“ nicht zu sehen war: beim Zurückkommen neu sortieren.
    @State private var visible = false
    @State private var stale = false
    /// Die Änderung kam von hier (Swipe, Rückgängig): Die oberste Karte bleibt liegen.
    @State private var ownChange = false

    struct Toast: Equatable {
        var text: String
        var symbol: String
        var color: Color
    }

    private let options: [SwipeDirection: SwipeOption] = [
        .left: .init(title: SwipeAction.notToday.title, symbol: SwipeAction.notToday.symbol, color: SwipeAction.notToday.color),
        .right: .init(title: SwipeAction.watchlist.title, symbol: SwipeAction.watchlist.symbol, color: SwipeAction.watchlist.color),
        .down: .init(title: SwipeAction.alreadySeen.title, symbol: SwipeAction.alreadySeen.symbol, color: SwipeAction.alreadySeen.color),
        .up: .init(title: SwipeAction.details.title, symbol: SwipeAction.details.symbol, color: SwipeAction.details.color, flyOut: false)
    ]

    var body: some View {
        let recs = queue
        VStack(spacing: 14) {
            header
            if let pending = store.pendingRatings.last, let film = FilmIndex.film(pending.filmID) {
                ratingBanner(pending, film)
            }
            if recs.isEmpty {
                emptyState
            } else {
                deck(recs)
                if store.homeSwipeCount < 3 {
                    SwipeLegend(options: options)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                controls(recs.first!.film)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .background { BlurredBackdrop(film: recs.first?.film) }
        .overlay(alignment: .top) {
            if let toast {
                Label(toast.text, systemImage: toast.symbol)
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white, toast.color)
                    .symbolEffect(.bounce, value: toast)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .glassEffect()
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .padding(.top, 54)
            }
        }
        .sheet(item: $detailFilm) { film in
            FilmDetailView(film: film)
                .navigationTransition(.zoom(sourceID: film.id, in: zoom))
        }
        .filmPlayer($playing, in: zoom)
        .fullScreenCover(isPresented: $addingProfile) {
            OnboardingFlow(mode: .addProfile, cancel: { addingProfile = false }) { id in
                if !store.activeProfileIDs.contains(id) { store.activeProfileIDs.append(id) }
                store.save()
                addingProfile = false
            }
        }
        .onAppear {
            visible = true
            if queue.isEmpty || stale { stale = false; rebuildQueue(animated: !queue.isEmpty) }
        }
        .onDisappear { visible = false }
        .onChange(of: store.tasteRevision) { _, _ in tasteChanged() }
        .onChange(of: store.activeProfileIDs) { _, _ in rebuildQueue(animated: true) }
        .onChange(of: store.runtimeFilter) { _, _ in rebuildQueue(animated: true) }
        .onChange(of: store.kindFilter) { _, _ in rebuildQueue(animated: true) }
        .onChange(of: store.pendingRatings.count) { _, _ in prune() }
        .task {
            if queue.isEmpty { rebuildQueue() }
            switch DemoScreen.current {
            case "detail": detailFilm = UserDefaults.standard.string(forKey: "detailID").flatMap(FilmIndex.film) ?? recs.first?.film
            case "player": if let f = recs.first?.film { playing = PlaybackRequest(film: f, episode: store.upNext(f), countsAsWatched: true, sourceID: f.id) }
            case "rating": store.ratingToPresent = store.pendingRatings.last
            default: break
            }
        }
    }

    // MARK: Kopfzeile

    /// Bewusst leise: Avatar, eine Zeile Text, zwei kleine Symbole. Der Film ist der Star.
    private var header: some View {
        HStack(spacing: 12) {
            ProfileMenu(onCreate: { addingProfile = true }, onManage: { store.selectedTab = 3 }) {
                AvatarStack(profiles: store.activeProfiles, size: 34)
                    .padding(4)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Wer schaut?")

            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text((["für heute"] + (store.kindFilter == .all ? [] : [store.kindFilter.title])
                      + (store.runtimeFilter.map { [$0.label] } ?? [])).joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .contentTransition(.interpolate)

            Spacer()

            Button {
                ownChange = true
                withAnimation(.snappy) { store.undo() }
                if let last = swiped.popLast() {
                    withAnimation(.smooth(duration: 0.35)) {
                        queue.removeAll { $0.id == last.id }
                        queue.insert(last, at: 0)
                    }
                }
                undoBounce += 1
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.headline)
                    .symbolEffect(.rotate.counterClockwise, value: undoBounce)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(!store.canUndo)
            .opacity(store.canUndo ? 1 : 0)
            .scaleEffect(store.canUndo ? 1 : 0.6)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.canUndo)
            .accessibilityLabel("Rückgängig")

            RuntimeMenu {
                let active = store.runtimeFilter != nil || store.kindFilter != .all
                Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.headline)
                    .foregroundStyle(active ? store.accent : Color.primary)
                    .frame(width: 42, height: 42)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Film oder Serie, Zeit")
        }
        .padding(.top, 4)
    }

    /// „Dein Film“ / „Deine Serie“, je nachdem, was oben liegt.
    private var headline: String {
        let together = store.activeProfiles.count > 1
        let series = queue.first?.film.isSeries ?? (store.kindFilter == .series)
        switch (together, series) {
        case (false, false): return "Dein Film"
        case (false, true): return "Deine Serie"
        case (true, false): return "Euer Film"
        case (true, true): return "Eure Serie"
        }
    }

    // MARK: Karten

    private func deck(_ recs: [Recommendation]) -> some View {
        // Kartenbreite aus der verfügbaren Höhe ableiten, damit das Poster ohne Ränder sitzt.
        GeometryReader { geo in
            let width = min(geo.size.width, (geo.size.height - RecommendationCard.infoHeight) * 2 / 3)
            SwipeDeck(items: recs, options: options, trigger: $trigger,
                      onCommit: { rec, direction in handle(direction, rec.film) },
                      onTap: { detailFilm = $0.film }) { rec, isTop in
                RecommendationCard(rec: rec, compact: !isTop, width: width)
                    // Form explizit setzen, sonst zeigt die Quelle vor der ersten Zoom-Animation
                    // ein eckiges Rechteck hinter den runden Ecken.
                    .matchedTransitionSource(id: rec.film.id, in: zoom) { $0.clipShape(.rect(cornerRadius: 28)).background(.clear) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxHeight: .infinity)
    }

    /// Nur eine Handlung: abspielen. Alles andere geht per Wischen.
    private func controls(_ film: Film) -> some View {
        Button {
            playing = PlaybackRequest(film: film, episode: store.upNext(film), countsAsWatched: true, sourceID: film.id)
        } label: {
            Label(store.playLabel(film), systemImage: "play.fill")
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(store.accent).interactive(), in: .capsule)
    }

    /// Jede Änderung am Geschmack (Swipe, Chat, Kalibrieren, Bewertung) wirkt sofort.
    /// Eigene Swipes lassen die oberste Karte liegen und sortieren nur dahinter neu,
    /// alles andere (z. B. der KI-Chat) baut den Stapel ganz neu auf.
    private func tasteChanged() {
        guard visible else { stale = true; return }
        if ownChange, let top = queue.first {
            ownChange = false
            let fresh = store.recommendations(limit: 6).filter { $0.id != top.id }
            PosterCache.warmUp(fresh.prefix(3).map(\.film.id))
            withAnimation(.smooth(duration: 0.4)) { queue = [top] + fresh.prefix(3) }
        } else {
            ownChange = false
            rebuildQueue(animated: true)
        }
    }

    private func rebuildQueue(animated: Bool = false) {
        let fresh = store.recommendations(limit: 4)
        PosterCache.warmUp(fresh.map(\.film.id))
        if animated { withAnimation(.smooth(duration: 0.4)) { queue = fresh } } else { queue = fresh }
        swiped = []
    }

    /// Filme entfernen, die nicht mehr in Frage kommen (z. B. gerade abgespielt), und auffüllen.
    private func prune() {
        let eligible = Set(RecommendationEngine.candidates(profiles: store.activeProfiles, runtime: store.runtimeFilter,
                                                           kind: store.kindFilter, skipped: store.skippedToday).map(\.id))
        withAnimation(.smooth(duration: 0.4)) {
            queue.removeAll { !eligible.contains($0.id) }
            let known = Set(queue.map(\.id))
            for next in store.recommendations(limit: 10) where queue.count < 4 && !known.contains(next.id) {
                queue.append(next)
            }
        }
    }

    /// Oberste Karte entfernen und hinten mit frischen Vorschlägen auffüllen.
    private func advance(past rec: Recommendation) {
        queue.removeAll { $0.id == rec.id }
        swiped.append(rec)
        if swiped.count > 20 { swiped.removeFirst() }
        let known = Set(queue.map(\.id)).union([rec.id])
        for next in store.recommendations(limit: 10) where queue.count < 4 && !known.contains(next.id) {
            queue.append(next)
        }
        PosterCache.warmUp(queue.map(\.film.id))
    }

    private func handle(_ direction: SwipeDirection, _ film: Film) {
        ownChange = direction != .up
        let rec = direction == .up ? nil : queue.first(where: { $0.film.id == film.id })
        defer { if let rec { advance(past: rec) } }
        if rec != nil { store.homeSwipeCount += 1 }
        switch direction {
        case .up:
            detailFilm = film
        case .left:
            store.apply(.notToday, to: film)
        case .right:
            store.apply(.watchlist, to: film)
            show("Auf der Merkliste", "bookmark.circle.fill", SwipeAction.watchlist.color)
        case .down:
            store.apply(.alreadySeen, to: film)
            show(film.isSeries ? "Wie fandest du sie? Oben bewerten" : "Wie fandest du ihn? Oben bewerten", "star.circle.fill", .yellow)
        }
    }

    private func show(_ text: String, _ symbol: String, _ color: Color) {
        let t = Toast(text: text, symbol: symbol, color: color)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.smooth) { if toast == t { toast = nil } }
        }
    }

    // MARK: Bewertung & Leerzustand

    private func ratingBanner(_ pending: PendingRating, _ film: Film) -> some View {
        Button { store.ratingToPresent = pending } label: {
            HStack(spacing: 12) {
                PosterView(film: film, cornerRadius: 6).frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Calendar.current.isDateInToday(pending.date) ? "Gerade geschaut" : "Gestern geschaut")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Wie war „\(film.title)“?").font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer()
                Image(systemName: "star.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2.5)))
            }
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "popcorn.fill").font(.system(size: 54)).foregroundStyle(.secondary)
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2)))
            Text("Für heute alles gesehen").font(.title2.weight(.bold))
            Text("Lockere die Filter, probier die Suche, oder hol die übersprungenen Titel zurück.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Übersprungene zurückholen") {
                withAnimation { store.skippedToday = []; store.runtimeFilter = nil; store.kindFilter = .all }
            }
            .buttonStyle(.glass)
            Spacer()
        }
        .padding()
    }
}

/// Die große Vorschlagskarte: Das Poster füllt die Karte, unten liegt in einem dunklen Verlauf
/// alles, was neugierig macht: Match, großer Titel, ein Satz über den Film und warum er passt.
struct RecommendationCard: View {
    let rec: Recommendation
    var compact = false
    var width: CGFloat? = nil
    @State private var shownMatch = 0

    /// Alles liegt auf dem Poster, unter der Karte braucht es keinen Platz mehr.
    static let infoHeight: CGFloat = 0

    var body: some View {
        PosterView(film: rec.film, cornerRadius: 0)
            .overlay(alignment: .bottom) { cover }
            .frame(width: width)
            .background(Color(white: 0.1))
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.08)))
            .animation(.smooth(duration: 0.3), value: compact)
            .cardShadow()
            .task(id: rec.id) {
                // Hinten liegende Karten zeigen den Wert gleich; nur die erste zählt sichtbar hoch.
                guard !compact else { shownMatch = rec.match; return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.smooth(duration: 0.9)) { shownMatch = rec.match }
            }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if rec.film.comingSoon {
                    Label(rec.film.releaseNote ?? "Demnächst", systemImage: "calendar")
                        .font(.subheadline.weight(.heavy))
                } else {
                    Text("\(shownMatch) % Match")
                        .font(.subheadline.weight(.heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownMatch)))
                        .foregroundStyle(Color.match(rec.match))
                }
                Text(rec.film.isSeries ? "\(rec.film.yearText) · \(rec.film.seasonsText)" : "\(String(rec.film.year)) · \(rec.film.runtimeText)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)

            Text(rec.film.title)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

            Text(rec.film.hook)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(compact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)

        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.bottom, 20).padding(.top, 90)
        .background {
            // Verlauf statt Kasten: Das Poster bleibt sichtbar, der Text trotzdem lesbar.
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                   .init(color: .black.opacity(0.75), location: 0.3),
                                   .init(color: .black.opacity(0.88), location: 0.55),
                                   .init(color: .black.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Zeitfilter

/// „Wie viel Zeit hast du?“ als natives Menü, wächst wie das Profilmenü aus dem Button.
/// Höchstens/Mindestens, Schnellwahl und ±15 Minuten für jede beliebige Dauer.
/// Das Menü bleibt beim Einstellen offen, der Stapel dahinter sortiert sich live um.
struct RuntimeMenu<MenuLabel: View>: View {
    @Environment(AppStore.self) private var store
    @ViewBuilder var label: () -> MenuLabel

    private var current: RuntimeFilter { store.runtimeFilter ?? RuntimeFilter(minutes: 120) }

    var body: some View {
        Menu {
            Section {
                Picker("Was möchtest du schauen?", selection: Binding(
                    get: { store.kindFilter },
                    set: { v in withAnimation(.snappy) { store.kindFilter = v } })) {
                    ForEach(KindFilter.allCases) { k in Text(k.title).tag(k) }
                }
                .pickerStyle(.palette)
                .menuActionDismissBehavior(.disabled)
            }
            Section {
                Picker(store.kindFilter == .series ? "Wie lang darf eine Folge sein?" : "Wie viel Zeit hast du?", selection: Binding(
                    get: { current.atLeast },
                    set: { v in set(RuntimeFilter(minutes: current.minutes, atLeast: v)) })) {
                    Text("Höchstens").tag(false)
                    Text("Mindestens").tag(true)
                }
                .pickerStyle(.palette)
                .menuActionDismissBehavior(.disabled)
            }
            Section {
                Picker(store.runtimeFilter.map { "\($0.atLeast ? "Mindestens" : "Höchstens") \(RuntimeFilter.duration($0.minutes)) · \(matching) Titel" } ?? "Dauer wählen", selection: Binding(
                    get: { store.runtimeFilter?.minutes ?? 0 },
                    set: { v in set(RuntimeFilter(minutes: v, atLeast: current.atLeast)) })) {
                    Text("1,5 Std.").tag(90)
                    Text("2 Std.").tag(120)
                    Text("2,5 Std.").tag(150)
                    Text("3 Std.").tag(180)
                }
                .pickerStyle(.palette)
                .menuActionDismissBehavior(.disabled)
                ControlGroup {
                    Button("15 Min. weniger", systemImage: "minus") { step(-15) }
                        .menuActionDismissBehavior(.disabled)
                    Button("15 Min. mehr", systemImage: "plus") { step(15) }
                        .menuActionDismissBehavior(.disabled)
                }
            }
            Section {
                Button("Egal, Zeit spielt keine Rolle", systemImage: "clock.badge.xmark") {
                    withAnimation(.snappy) { store.runtimeFilter = nil }
                }
            }
        } label: {
            label()
        }
        .sensoryFeedback(.selection, trigger: store.runtimeFilter)
        .sensoryFeedback(.selection, trigger: store.kindFilter)
        .accessibilityLabel("Film oder Serie, Zeit")
    }

    private var matching: Int {
        RecommendationEngine.candidates(profiles: store.activeProfiles, runtime: store.runtimeFilter,
                                        kind: store.kindFilter, skipped: store.skippedToday).count
    }

    private func step(_ delta: Int) {
        set(RuntimeFilter(minutes: (current.minutes + delta).clamped(to: 60...240), atLeast: current.atLeast))
    }

    private func set(_ filter: RuntimeFilter) {
        withAnimation(.snappy) { store.runtimeFilter = filter }
    }
}
