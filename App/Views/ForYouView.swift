import SwiftUI

/// Startseite: genau ein Vorschlag. Wischen statt Scrollen.
struct ForYouView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var playing: PlaybackRequest?
    @Namespace private var zoom
    @State private var trigger: SwipeDirection?
    /// Details öffnen sich als Morph über der ganzen App (siehe `HeroOverlay`).
    @Environment(HeroCoordinator.self) private var hero
    @State private var addingProfile = false
    @State private var managingProfiles = false
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
    /// Gewischt, aber noch nicht gelernt (läuft, sobald die Karte weggeflogen ist).
    @State private var pendingWork: [(id: UUID, work: () -> Void)] = []

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
        GeometryReader { geometry in
            let expanded = sizeClass == .regular && geometry.size.width >= 760 && geometry.size.height >= 500 && !typeSize.isAccessibilitySize
            VStack(spacing: expanded ? 24 : 14) {
                header
                if let pending = store.pendingRatings.last, let film = FilmIndex.film(pending.filmID) {
                    ratingBanner(pending, film)
                }
                if recs.isEmpty {
                    emptyState
                } else if expanded, let rec = recs.first {
                    HStack(spacing: 36) {
                        deck(recs, topAligned: true)
                            .id(store.activeProfileIDs)
                            .frame(maxWidth: geometry.size.width * 0.46)
                        tabletInformation(rec)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    deck(recs)
                        .id(store.activeProfileIDs)
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                    if store.homeSwipeCount < 3 {
                        SwipeLegend(options: options)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    controls(recs.first!.film)
                }
            }
            .padding(.horizontal, expanded ? 36 : 18)
            .padding(.bottom, expanded ? 24 : 6)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
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
        .filmPlayer($playing, in: zoom)
        .fullScreenCover(isPresented: $managingProfiles) {
            NavigationStack { ManageProfilesView() }
        }
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
        // Sobald ein Poster da ist, auch seinen Hintergrund vorbereiten.
        .onChange(of: queue.map(\.id)) { _, _ in BackdropBlur.warmUp(queue.prefix(4).map(\.film.id)) }
        .task {
            if queue.isEmpty { rebuildQueue() }
            switch DemoScreen.current {
            case "detail": if let f = UserDefaults.standard.string(forKey: "detailID").flatMap(FilmIndex.film) ?? recs.first?.film { hero.show(f, from: "foryou") }
            case "player": if let f = recs.first?.film { playing = PlaybackRequest(film: f, episode: store.upNext(f), countsAsWatched: true, sourceID: f.id) }
            case "rating": store.ratingToPresent = store.pendingRatings.last
            default: break
            }
        }
    }

    /// Wide windows keep the touch deck while bringing useful detail alongside it.
    private func tabletInformation(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(rec.film.hook)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rec.film.metaLine)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(rec.film.genres.joined(separator: " · "))
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 18) {
                        if let rating = rec.film.imdbRating {
                            Label("IMDb \(rating.formatted(.number.precision(.fractionLength(1))))", systemImage: "star.fill")
                        }
                        if let tomatoes = rec.film.rottenTomatoes { Text("Rotten Tomatoes \(tomatoes) %") }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if rec.film.synopsis != rec.film.hook {
                        Text(rec.film.synopsis).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Warum dieser Film?").font(.headline).foregroundStyle(store.accent)
                        Text(rec.reason).font(.body)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Regie · \(rec.film.director)")
                        Text(rec.film.cast.prefix(3).joined(separator: " · "))
                    }.font(.footnote).foregroundStyle(.secondary)
                    Button("Alle Filmdetails", systemImage: "info.circle") {
                        hero.show(rec.film, from: "foryou")
                    }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            SwipeLegend(options: options)
            controls(rec.film)
        }
    }

    // MARK: Kopfzeile

    /// Bewusst leise: Avatar, eine Zeile Text, zwei kleine Symbole. Der Film ist der Star.
    private var header: some View {
        HStack(spacing: 12) {
            ProfileMenu(onCreate: { addingProfile = true }, onManage: { managingProfiles = true }) {
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
                runPendingWork()
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
            // Keep navigation in a fixed place; unavailable undo is disabled, never hidden.
            .disabled(!store.canUndo)
            .accessibilityLabel("Rückgängig")
            .accessibilityHint(store.canUndo ? "Macht den letzten Film-Swipe rückgängig" : "Noch kein Film-Swipe zum Rückgängigmachen")

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

    private func deck(_ recs: [Recommendation], topAligned: Bool = false) -> some View {
        // Kartenbreite aus der verfügbaren Höhe ableiten, damit das Poster ohne Ränder sitzt.
        GeometryReader { geo in
            let width = min(geo.size.width, (geo.size.height - RecommendationCard.infoHeight) * 2 / 3)
            SwipeDeck(items: recs, options: options, trigger: $trigger,
                      onCommit: { rec, direction in handle(direction, rec.film) },
                      onTap: { hero.show($0.film, from: "foryou") }) { rec, isTop in
                RecommendationCard(rec: rec, compact: !isTop, width: width, viewers: store.activeProfileIDs.count,
                                   heroScope: "foryou")
                    // Form explizit setzen, sonst zeigt die Quelle vor der ersten Zoom-Animation
                    // ein eckiges Rechteck hinter den runden Ecken.
                    .matchedTransitionSource(id: rec.film.id, in: zoom) { $0.clipShape(.rect(cornerRadius: 28)).background(.clear) }
            }
            .frame(width: geo.size.width, height: topAligned ? min(geo.size.height, width * 1.5) : geo.size.height)
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
            PosterCache.warmUp(fresh.prefix(3).map(\.film.id)); BackdropBlur.warmUp(fresh.prefix(3).map(\.film.id))
            withAnimation(.smooth(duration: 0.4)) { queue = [top] + fresh.prefix(3) }
        } else {
            ownChange = false
            rebuildQueue(animated: true)
        }
    }

    private func rebuildQueue(animated: Bool = false) {
        let fresh = store.recommendations(limit: 4)
        PosterCache.warmUp(fresh.map(\.film.id)); BackdropBlur.warmUp(fresh.prefix(4).map(\.film.id))
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
        // Hinten auffüllen erst nach dem Abflug, die nächsten drei Karten liegen ja schon bereit.
        Task {
            // Erst wenn die nachgerückte Karte ausgefedert ist, sonst schneidet das Auffüllen die Animation ab.
            try? await Task.sleep(for: .milliseconds(750))
            guard queue.count < 4 else { return }
            let known = Set(queue.map(\.id)).union(swiped.map(\.id))
            for next in store.recommendations(limit: 10) where queue.count < 4 && !known.contains(next.id) {
                queue.append(next)
            }
            PosterCache.warmUp(queue.map(\.film.id)); BackdropBlur.warmUp(queue.map(\.film.id))
        }
    }

    private func handle(_ direction: SwipeDirection, _ film: Film) {
        let rec = direction == .up ? nil : queue.first(where: { $0.film.id == film.id })
        defer { if let rec { advance(past: rec) } }
        if rec != nil { store.homeSwipeCount += 1 }
        switch direction {
        case .up:
            hero.show(film, from: "foryou")
        case .left:
            afterFlight { store.apply(.notToday, to: film) }
        case .right:
            afterFlight { store.apply(.watchlist, to: film) }
            show("Auf der Merkliste", "bookmark.circle.fill", SwipeAction.watchlist.color)
        case .down:
            afterFlight { store.apply(.alreadySeen, to: film) }
            show(film.isSeries ? "Wie fandest du sie? Oben bewerten" : "Wie fandest du ihn? Oben bewerten", "star.circle.fill", .yellow)
        }
    }

    /// Lernen und Neusortieren erst, wenn die Karte weg ist: Während sie fliegt,
    /// bekommt die Animation die volle Rechenzeit.
    private func afterFlight(_ work: @escaping () -> Void) {
        let id = UUID()
        pendingWork.append((id, work))
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard let i = pendingWork.firstIndex(where: { $0.id == id }) else { return }
            // Erst hier als eigene Änderung markieren: Sonst baut ein später verarbeiteter Swipe
            // den ganzen Stapel neu auf, z. B. während gerade die Details der obersten Karte aufgehen.
            ownChange = true
            pendingWork.remove(at: i).work()
        }
    }

    /// Noch ausstehendes Lernen sofort erledigen (z. B. vor „Rückgängig“).
    private func runPendingWork() {
        let work = pendingWork
        pendingWork = []
        work.forEach { $0.work() }
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
    /// Wie viele zusammen schauen: Der Match gilt dann für alle gemeinsam.
    var viewers = 1
    /// Bereich für den Morph zu den Details. Cover und Titel fliegen dann als eigene Ebene,
    /// Match und Einzeiler blenden aus, solange die Details offen sind.
    var heroScope: String? = nil
    /// Nur für die fliegende Ebene: gesetzt heißt „ich bin die Karte im Flug“, `true` = schon bei den Details.
    var ghostOpen: Bool? = nil
    var cornerRadius: CGFloat = 28
    @Environment(HeroCoordinator.self) private var hero
    private var lifted: Bool { heroScope.map { hero.isLifted(rec.film.id, in: $0) } ?? false }
    private var detailsUp: Bool { heroScope.map { hero.isShowingDetails(rec.film.id, in: $0) } ?? false }
    @State private var shownMatch = 0

    static let titleFont = Theme.recommendationTitle(size: 36)
    static let shade = LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                              .init(color: .black.opacity(0.75), location: 0.3),
                                              .init(color: .black.opacity(0.88), location: 0.55),
                                              .init(color: .black.opacity(0.95), location: 1)],
                                      startPoint: .top, endPoint: .bottom)

    /// Alles liegt auf dem Poster, unter der Karte braucht es keinen Platz mehr.
    static let infoHeight: CGFloat = 0

    var body: some View {
        let atDetails = ghostOpen ?? false
        PosterView(film: rec.film, cornerRadius: 0, showsBadge: ghostOpen == nil)
            // Verlauf, Match, Laufzeit und Einzeiler blenden im Flug zum Detail-Cover aus und zurück ein.
            .overlay(alignment: .bottom) { cover.opacity(atDetails ? 0 : 1) }
            .frame(width: width)
            .background(Color(white: 0.1))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(atDetails ? 0.12 : 0.08)))
            // Während die Karte fliegt, bleibt hier nur ihr Schatten als Platzhalter.
            .opacity(lifted ? 0 : 1)
            .modifier(OptionalHeroSource(rec: rec, scope: heroScope))
            .animation(.smooth(duration: 0.3), value: compact)
            .background {
                if ghostOpen == nil {
                    // Schatten der Karte; solange sie fliegt, trägt die fliegende Ebene ihn. Die Fläche bleibt
                    // als Platzhalter und deckt die nächste Karte ab, bis die Detailseite darüber liegt.
                    RoundedRectangle(cornerRadius: 28).fill(.black)
                        .shadow(color: .black.opacity(lifted ? 0 : 0.5), radius: 24, y: 12)
                        // Erst weg, wenn die Detailseite ganz steht. Sonst scheint im Flug die nächste Karte durch.
                        .opacity(detailsUp && hero.ghost == nil ? 0 : 1)
                }
            }
            .task(id: "\(rec.id)-\(rec.match)-\(viewers)") {
                // Hinten liegende Karten zeigen den Wert gleich; nur die erste zählt sichtbar hoch.
                guard !compact, ghostOpen == nil else { shownMatch = rec.match; return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.smooth(duration: 0.9)) { shownMatch = rec.match }
            }
    }

    /// Die fliegende Karte zeigt den Wert gleich, sie soll nicht noch einmal hochzählen.
    private var displayedMatch: Int { ghostOpen == nil ? shownMatch : rec.match }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if rec.film.comingSoon {
                    Label(rec.film.releaseNote ?? "Demnächst", systemImage: "calendar")
                        .font(.subheadline.weight(.heavy))
                } else {
                    Text(viewers > 1 ? "\(displayedMatch) % für euch \(viewers == 2 ? "beide" : "\(viewers)")" : "\(displayedMatch) % Match")
                        .font(.subheadline.weight(.heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(displayedMatch)))
                        .foregroundStyle(Color.match(rec.match))
                }
                Text(rec.film.isSeries ? "\(rec.film.yearText) · \(rec.film.seasonsText)" : "\(String(rec.film.year)) · \(rec.film.runtimeText)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)

            Text(rec.film.title)
                .font(RecommendationCard.titleFont)
                .lineLimit(2).minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

            RedactedText(rec.film.hook)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.88))
                // Immer drei Zeilen: Ein Umspringen beim Nachrücken würde den Text stückweise neu aufbauen.
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.bottom, 20).padding(.top, 90)
        .background {
            // Verlauf statt Kasten: Das Poster bleibt sichtbar, der Text trotzdem lesbar.
            Self.shade
        }
    }
}

// MARK: - Zeitfilter

/// Film oder Serie und „Wie viel Zeit hast du?“ als natives Menü, wächst wie das Profilmenü aus dem Button.
/// Darunter Mindest- und Höchstdauer, je „Egal“ oder eine von drei Dauern.
/// Das Menü bleibt beim Einstellen offen, der Stapel dahinter sortiert sich live um.
struct RuntimeMenu<MenuLabel: View>: View {
    @Environment(AppStore.self) private var store
    @ViewBuilder var label: () -> MenuLabel


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
            Section(timeTitle) {
                bound("Mindestens", options: [60, 90, 120], value: store.runtimeFilter?.min, isMin: true)
                bound("Höchstens", options: [90, 120, 180], value: store.runtimeFilter?.max, isMin: false)
            }
            if store.runtimeFilter != nil || store.kindFilter != .all {
                Section {
                    Button("Filter zurücksetzen", systemImage: "arrow.counterclockwise") {
                        withAnimation(.snappy) { store.runtimeFilter = nil; store.kindFilter = .all }
                    }
                }
            }
        } label: {
            label()
        }
        .sensoryFeedback(.selection, trigger: store.runtimeFilter)
        .sensoryFeedback(.selection, trigger: store.kindFilter)
        .accessibilityLabel("Film oder Serie, Zeit")
    }

    /// Überschrift der Zeit: die Frage, oder die aktuelle Wahl mit Trefferzahl.
    private var timeTitle: String {
        guard let filter = store.runtimeFilter else {
            return store.kindFilter == .series ? "Wie lang darf eine Folge sein?" : "Wie viel Zeit hast du?"
        }
        return "\(filter.label) · \(matching) Titel"
    }

    private var matching: Int {
        RecommendationEngine.candidates(profiles: store.activeProfiles, runtime: store.runtimeFilter,
                                        kind: store.kindFilter, skipped: store.skippedToday).count
    }

    /// Eine Zeile je Grenze: Egal oder eine von drei Dauern.
    private func bound(_ title: String, options: [Int], value: Int?, isMin: Bool) -> some View {
        Picker(title, selection: Binding(get: { value ?? 0 }, set: { change(isMin, $0 == 0 ? nil : $0) })) {
            Text("Egal").tag(0)
            ForEach(options, id: \.self) { Text(RuntimeFilter.short($0)).tag($0) }
        }
        .pickerStyle(.palette)
        .menuActionDismissBehavior(.disabled)
    }

    /// Die andere Grenze rückt mit, damit der Bereich nie leer wird.
    private func change(_ isMin: Bool, _ value: Int?) {
        var filter = store.runtimeFilter ?? RuntimeFilter()
        if isMin {
            filter.min = value
            if let value, let hi = filter.max, hi < value { filter.max = value }
        } else {
            filter.max = value
            if let value, let lo = filter.min, lo > value { filter.min = value }
        }
        set(filter.min == nil && filter.max == nil ? nil : filter)
    }

    private func set(_ filter: RuntimeFilter?) {
        withAnimation(.snappy) { store.runtimeFilter = filter }
    }
}

// MARK: - Details als Morph

/// Das Cover fliegt von seinem Platz (Karte, Merkliste, Katalog, Suche) an seinen Platz auf der
/// Detailseite und zurück. Die Detailseite liegt über der ganzen App (auch über der Tab-Leiste),
/// deshalb bleibt das Layout dahinter unverändert und Start- und Zielpunkt stimmen exakt.
/// Beide Punkte werden in Bildschirmkoordinaten gemessen, das fliegende Cover ist eine eigene Ebene.
@Observable @MainActor
final class HeroCoordinator {
    /// Woher ein Cover losfliegt: Rahmen, Ecken und ob es eine Vorschlagskarte ist
    /// (dann fliegen Verlauf und Titel mit).
    struct Source {
        var frame: CGRect
        var radius: CGFloat
        var rec: Recommendation?
        var card: Bool { rec != nil }
    }

    private(set) var film: Film?
    /// Bereich, aus dem die Details geöffnet wurden. Derselbe Film kann an mehreren Stellen stehen.
    private(set) var scope: String?
    private(set) var open = false
    /// Das fliegende Cover, solange es unterwegs ist.
    private(set) var ghost: Film?
    /// Ändern sich bei jedem Scrollen; nur der Flug selbst liest sie, darum ohne Beobachtung.
    @ObservationIgnored var sources: [String: Source] = [:]
    var detailFrame: CGRect = .zero
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    /// Während des Rückflugs angetippt: danach direkt öffnen statt den Tipp zu verlieren.
    @ObservationIgnored private var closingNow = false
    @ObservationIgnored private var pendingShow: (Film, String)?

    static func key(_ id: String, _ scope: String) -> String { scope + "|" + id }

    /// Cover und Titel an der Quelle verstecken, solange die Details offen sind oder es fliegt.
    func isLifted(_ id: String, in scope: String) -> Bool { film?.id == id && self.scope == scope }
    /// Match und Einzeiler der Karte: weg, sobald die Details aufgehen, zurück, sobald sie zugehen.
    func isShowingDetails(_ id: String, in scope: String) -> Bool { isLifted(id, in: scope) && open }

    var source: Source? { film.flatMap { f in scope.flatMap { sources[Self.key(f.id, $0)] } } }

    func show(_ film: Film, from scope: String) {
        if self.film != nil {
            if closingNow { pendingShow = (film, scope) }
            return
        }
        transitionTask?.cancel()
        open = false
        detailFrame = .zero
        self.scope = scope
        ghost = sources[Self.key(film.id, scope)] == nil ? nil : film
        self.film = film
        transitionTask = Task {
            // Warten, bis die Detailseite steht und ihr Cover gemessen ist.
            for _ in 0..<20 where detailFrame == .zero {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { open = true }
            try? await Task.sleep(for: .milliseconds(560))
            guard !Task.isCancelled else { return }
            if open { ghost = nil }
        }
    }

    func close() {
        guard let film else { return }
        guard !closingNow else { return }
        transitionTask?.cancel()
        // A close before layout must not let a stale opening task present later.
        guard open else {
            self.film = nil; scope = nil; ghost = nil
            return
        }
        // Ist die Quelle verschwunden (z. B. von der Merkliste genommen), blendet die Seite nur aus.
        let flies = source != nil
        let alreadyFlying = ghost != nil
        if flies { ghost = film }
        closingNow = true
        if alreadyFlying || !flies {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) { open = false }
        }
        transitionTask = Task {
            // Erst einen Frame mit dem Cover an der Detailposition zeigen, dann losfliegen.
            if flies && !alreadyFlying { try? await Task.sleep(for: .milliseconds(20)) }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) { open = false }
            try? await Task.sleep(for: .milliseconds(flies ? 460 : 380))
            closingNow = false
            guard !open else { return }
            // Gelandet: Cover und Titel der Quelle übernehmen ohne Sprung.
            self.film = nil
            scope = nil
            ghost = nil
            if let (next, nextScope) = pendingShow {
                pendingShow = nil
                show(next, from: nextScope)
            }
        }
    }
}

extension View {
    /// Macht ein Cover zum Startpunkt des Morphs: misst seine Lage und blendet es aus, solange es fliegt.
    func heroSource(_ film: Film, in scope: String, cornerRadius: CGFloat) -> some View {
        modifier(HeroSourceModifier(film: film, scope: scope, radius: cornerRadius))
    }
}

/// Karten ohne Bereich (z. B. Vorschau) messen nichts.
private struct OptionalHeroSource: ViewModifier {
    let rec: Recommendation
    let scope: String?
    func body(content: Content) -> some View {
        if let scope { content.modifier(HeroSourceModifier(film: rec.film, scope: scope, radius: 28, rec: rec)) } else { content }
    }
}

private struct HeroSourceModifier: ViewModifier {
    @Environment(HeroCoordinator.self) private var hero
    let film: Film
    let scope: String
    let radius: CGFloat
    /// Gesetzt bei Vorschlagskarten: Dann fliegt die ganze Karte mit Verlauf und Text.
    var rec: Recommendation? = nil

    /// Letzte Lage merken: Nach einem Tabwechsel meldet sich die Geometrie nicht neu,
    /// wenn sich nichts bewegt hat. Ohne Merken gäbe es dann keinen Startpunkt mehr.
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        let key = HeroCoordinator.key(film.id, scope)
        content
            // Die Karte versteckt sich selbst und lässt ihren Schatten als Platzhalter stehen.
            .opacity(rec == nil && hero.isLifted(film.id, in: scope) ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                frame = $0
                hero.sources[key] = .init(frame: $0, radius: radius, rec: rec)
            }
            .onAppear { if let frame { hero.sources[key] = .init(frame: frame, radius: radius, rec: rec) } }
            .onDisappear { hero.sources[key] = nil }
    }
}

struct HeroOverlay: View {
    @Environment(HeroCoordinator.self) private var hero
    @Environment(AppStore.self) private var store

    var body: some View {
        let source = hero.source
        ZStack {
            if let film = hero.film {
                FilmDetailView(film: film, posterHidden: hero.ghost != nil,
                               contentVisible: hero.open,
                               onClose: hero.close, onPosterFrame: { hero.detailFrame = $0 })
            }
            // Ganzer Bildschirm ohne Ränder: Hier entsprechen die Koordinaten denen der Messung.
            GeometryReader { _ in
                if let film = hero.ghost, let source {
                    let r = hero.open ? hero.detailFrame : source.frame
                    // Schatten wie am jeweiligen Ort: Karte groß und weich, Detail-Cover etwas enger,
                    // kleine Listen-Cover ohne. Er wandert stufenlos mit.
                    RoundedRectangle(cornerRadius: hero.open ? 14 : source.radius)
                        .fill(.black)
                        .frame(width: r.width, height: r.height)
                        .shadow(color: .black.opacity(hero.open || source.card ? 0.5 : 0),
                                radius: hero.open ? 18 : 24, y: hero.open ? 10 : 12)
                        .position(x: r.midX, y: r.midY)
                    if let rec = source.rec {
                        // Die ganze Karte fliegt: in Kartengröße gezeichnet und auf die aktuelle Größe skaliert,
                        // so sitzen Verlauf und Text genau wie auf der Karte. Die Ecken enden bei 14 pt am Ziel.
                        let s = source.frame.size
                        let scale = r.width / max(s.width, 1)
                        let detailScale = max(hero.detailFrame.width / max(s.width, 1), 0.01)
                        RecommendationCard(rec: rec, width: s.width, viewers: store.activeProfileIDs.count,
                                           ghostOpen: hero.open,
                                           cornerRadius: hero.open ? 14 / detailScale : source.radius)
                            .frame(width: s.width, height: s.height)
                            .scaleEffect(scale)
                            .position(x: r.midX, y: r.midY)
                    } else {
                        PosterView(film: film, cornerRadius: 0, showsBadge: false)
                            .frame(width: r.width, height: r.height)
                            .clipShape(.rect(cornerRadius: hero.open ? 14 : source.radius))
                            .overlay(RoundedRectangle(cornerRadius: hero.open ? 14 : source.radius)
                                .strokeBorder(.white.opacity(hero.open ? 0.12 : 0), lineWidth: 0.5))
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

/// Text, in dem Sternchen als Zensurbalken erscheinen: „über den ***** ****“.
/// Für Einzeiler mit Insider-Witz, bei denen man lieber nichts verraten will.
struct RedactedText: View {
    let string: String
    init(_ string: String) { self.string = string }

    var body: some View {
        var result = Text("")
        var rest = Substring(string)
        while let match = rest.firstMatch(of: /\*+/) {
            let hidden = Text(String(repeating: "█", count: match.output.count)).accessibilityLabel("geschwärzt")
            result = Text("\(result)\(Text(rest[..<match.range.lowerBound]))\(hidden)")
            rest = rest[match.range.upperBound...]
        }
        return Text("\(result)\(Text(rest))")
    }
}
