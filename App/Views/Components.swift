import CoreImage
import SwiftUI

// MARK: - Poster

struct PosterView: View {
    let film: Film
    var cornerRadius: CGFloat = 16
    var showsBadge = true

    var body: some View {
        let image = film.posterImage
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .transition(.opacity)
                } else {
                    // Deckender Platzhalter, nie durchsichtig, auch wenn ein Poster fehlt.
                    LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                        .overlay(Text(film.title).font(.headline).multilineTextAlignment(.center).padding())
                }
            }
            // Frisch geladene Poster blenden weich ein statt aufzuploppen.
            .animation(.easeOut(duration: 0.3), value: image != nil)
            .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(alignment: .topLeading) {
            if film.isSeries && showsBadge {
                Text("SERIE").font(.system(size: 10, weight: .heavy)).tracking(1.2)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .padding(8)
            }
        }
        .overlay {
            if film.comingSoon && showsBadge {
                VStack {
                    HStack {
                        Text("DEMNÄCHST").font(.caption2.weight(.heavy)).tracking(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(.black)
                            .background(.white, in: .capsule)
                        Spacer()
                    }
                    Spacer()
                }.padding(8)
            }
        }
    }
}

// MARK: - Profil-Avatar

struct AvatarView: View {
    let profile: Profile
    var size: CGFloat = 44
    var selected = true

    var body: some View {
        AvatarTile(art: profile.avatarArt, initial: profile.initial, color: profile.color, size: size, circle: true)
            .overlay(alignment: .bottomTrailing) {
                if profile.isKid {
                    Image(systemName: "figure.child")
                        .font(.system(size: size * 0.22, weight: .bold))
                        .padding(size * 0.06)
                        .background(.black, in: .circle)
                        .offset(x: 2, y: 2)
                }
            }
            .opacity(selected ? 1 : 0.35)
            .saturation(selected ? 1 : 0)
    }
}

/// Überlappende Avatare aller Profile, die gerade zusammen schauen.
struct AvatarStack: View {
    let profiles: [Profile]
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(profiles) { p in
                AvatarView(profile: p, size: size)
                    .overlay(Circle().stroke(.black, lineWidth: 2))
            }
        }
    }
}

// MARK: - Chips

struct TagChip: View {
    let text: String
    var tint: Color = .white
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.16), in: .capsule)
            .foregroundStyle(tint == .white ? .white.opacity(0.9) : tint)
    }
}

struct MatchBadge: View {
    let match: Int
    var body: some View {
        Text("\(match) % Match")
            .contentTransition(.numericText(value: Double(match)))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.match(match))
            .animation(.smooth, value: match)
    }
}

/// Match als Ring: füllt sich beim Erscheinen, Zahl zählt mit.
struct MatchRing: View {
    let match: Int
    /// Zielwert bestimmt die Farbe, damit sie beim Hochzählen nicht flackert.
    var target: Int? = nil
    var size: CGFloat = 50

    var body: some View {
        let color = Color.match(target ?? match)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(match) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(match)")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(match)))
                Text("%").font(.system(size: size * 0.18, weight: .bold, design: .rounded))
            }
            .monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(match) Prozent Match")
    }
}

extension Color {
    static func match(_ m: Int) -> Color {
        m >= 85 ? Color(red: 0.3, green: 0.9, blue: 0.55) : m >= 65 ? .yellow : .orange
    }
}

// MARK: - Haptik-Helfer

extension View {
    /// Schatten aus einer Form statt aus dem Karteninhalt: Den kann das System einmal
    /// berechnen, statt ihn beim Wischen in jedem Bild neu aus dem Poster abzuleiten.
    func cardShadow(cornerRadius: CGFloat = 28) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.black)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
    }
}

/// Unscharfer Poster-Hintergrund für Detail- und Startseiten.
/// Wechsel ohne dunkles Zwischenbild: Das neue Bild blendet *über* dem alten ein,
/// erst danach verschwindet das alte.
/// Unschärfe einmal vorab auf das kleine Vorschaubild rechnen statt live in jedem Frame.
/// Sonst muss die GPU beim Wischen zwei bildschirmgroße Ebenen gleichzeitig weichzeichnen.
enum BackdropBlur {
    private static var cache: [String: UIImage] = [:]
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(_ filmID: String) -> UIImage? {
        if let cached = cache[filmID] { return cached }
        guard let thumb = FilmIndex.film(filmID)?.posterThumbnail, let cg = thumb.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        guard let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: Double(input.extent.width) / 14)
                .cropped(to: input.extent) as CIImage?,
              let out = context.createCGImage(blurred, from: input.extent) else { return thumb }
        let image = UIImage(cgImage: out)
        if cache.count > 40 { cache.removeAll() }
        cache[filmID] = image
        return image
    }
}

struct BlurredBackdrop: View {
    let film: Film?

    private struct Layer: Equatable {
        var filmID: String?
        var generation: Int
    }
    @State private var layer = Layer(filmID: nil, generation: 0)

    var body: some View {
        ZStack {
            Color.black
            ForEach([layer], id: \.generation) { l in
                if let id = l.filmID, let image = BackdropBlur.image(id) {
                    // Color.clear legt die Größe fest, das Bild darf das Layout nicht aufblähen.
                    // Jede Ebene ist deckend (Bild auf Schwarz), so verdeckt die neue die alte
                    // vollständig, und beim Entfernen der alten ändert sich nichts mehr.
                    Color.black.overlay {
                        Image(uiImage: image)
                            .resizable().interpolation(.high).scaledToFill()
                            .opacity(0.55)
                            .scaleEffect(1.3)
                    }
                    .clipped()
                    .zIndex(Double(l.generation))
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.45)),
                        removal: .opacity.animation(.easeOut(duration: 0.2).delay(0.45))))
                }
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .zIndex(1_000_000)
        }
        .ignoresSafeArea()
        .onChange(of: film?.id, initial: true) { old, new in
            guard new != layer.filmID else { return }
            let next = Layer(filmID: new, generation: layer.generation + 1)
            if layer.filmID == nil && old == new { layer = next } else { withAnimation { layer = next } }
        }
    }
}

// MARK: - Bewertungen (IMDb · Rotten Tomatoes · Metacritic)

struct ScoreBadges: View {
    let film: Film
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            if let imdb = film.imdbRating {
                HStack(spacing: 4) {
                    Text("IMDb")
                        .font(.system(size: compact ? 9 : 10, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: .rect(cornerRadius: 3))
                    Text(imdb, format: .number.precision(.fractionLength(1)))
                        .contentTransition(.numericText(value: imdb))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("IMDb \(imdb, format: .number.precision(.fractionLength(1)))")
            }
            if let rt = film.rottenTomatoes {
                HStack(spacing: 3) {
                    Text(rt >= 60 ? "🍅" : "🤢").font(.system(size: compact ? 11 : 13))
                    Text("\(rt) %")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rotten Tomatoes \(rt) Prozent")
            }
            if let mc = film.metascore, !compact {
                Text("\(mc)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 20)
                    .background(mc >= 61 ? Color(red: 0.4, green: 0.8, blue: 0.2) : mc >= 40 ? .yellow : .red, in: .rect(cornerRadius: 3))
                    .accessibilityLabel("Metascore \(mc)")
            }
        }
        .font((compact ? Font.caption : .subheadline).weight(.semibold))
        .monospacedDigit()
    }
}

// MARK: - Trailer-Auswahl

struct TrailerPicker: View {
    let film: Film
    var namespace: Namespace.ID
    var onPick: (Trailer) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(film.trailers) { trailer in
                    Button { onPick(trailer) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: trailer.thumbnailURL, transaction: Transaction(animation: .smooth)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill().transition(.opacity)
                                } else {
                                    Rectangle().fill(.white.opacity(0.08))
                                }
                            }
                            .frame(width: 200, height: 112)
                            .clipShape(.rect(cornerRadius: 14))
                            .matchedTransitionSource(id: trailer.id, in: namespace)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(in: .circle)
                            }
                            .overlay(alignment: .topLeading) {
                                Text(trailer.german ? "DE" : "OV")
                                    .font(.caption2.weight(.heavy))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(.black.opacity(0.6), in: .capsule)
                                    .padding(8)
                            }
                            Text(trailer.title).font(.subheadline.weight(.semibold))
                            Text(trailer.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 200, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .scrollTransition(axis: .horizontal) { view, phase in
                        view.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .padding(.horizontal, -20)
    }
}

/// Altersfreigabe im Stil der FSK-Kennzeichen.
struct FSKBadge: View {
    let fsk: Int
    var color: Color {
        switch fsk {
        case 0: .white
        case 6: .yellow
        case 12: .green
        case 16: .blue
        default: .red
        }
    }
    var body: some View {
        Text("FSK \(fsk)")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1.2))
            .fixedSize()
    }
}

// MARK: - Profilwahl (wie Apple TV: Liquid-Glass-Menü aus dem Profil-Button)

struct ProfileMenu<MenuLabel: View>: View {
    @Environment(AppStore.self) private var store
    var onCreate: () -> Void
    var onManage: () -> Void
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            Section("Wer schaut?") {
                ForEach(store.profiles) { profile in
                    Toggle(isOn: binding(for: profile)) {
                        Label {
                            Text(profile.name)
                            Text(store.isPaused(profile.id) ? "Pausiert, nicht im Tarif enthalten"
                                 : profile.isKid ? profile.ageLabel : "\(profile.signalCount) Geschmackssignale")
                        } icon: {
                            Image(uiImage: AvatarImage.render(profile))
                        }
                    }
                    // Mehrere Profile hintereinander antippen, ohne dass das Menü zugeht.
                    .menuActionDismissBehavior(.disabled)
                    .disabled(store.isPaused(profile.id))
                }
            }
            Section {
                Button("Profil erstellen", systemImage: "plus", action: onCreate)
                Button("Profile verwalten", systemImage: "person.crop.circle", action: onManage)
            }
        } label: {
            label()
        }
        .sensoryFeedback(.selection, trigger: store.activeProfileIDs)
    }

    private func binding(for profile: Profile) -> Binding<Bool> {
        Binding(
            get: { store.activeProfileIDs.contains(profile.id) },
            set: { on in
                withAnimation(.smooth) {
                    if on && store.subscription?.plan.allowsTogether == false {
                        store.activeProfileIDs = [profile.id]
                    } else if on {
                        store.activeProfileIDs.append(profile.id)
                    } else if store.activeProfileIDs.count > 1 {
                        store.activeProfileIDs.removeAll { $0 == profile.id }
                    }
                    // Reihenfolge wie in der Profilliste, neue Runde = neue Vorschläge.
                    store.activeProfileIDs = store.profiles.map(\.id).filter(store.activeProfileIDs.contains)
                    store.skippedToday = []
                    store.save()
                }
            })
    }
}

/// Avatar als Bild für Menüeinträge (Menüs nehmen nur Bilder, keine beliebigen Views).
enum AvatarImage {
    private static var cache: [String: UIImage] = [:]

    static func render(_ profile: Profile) -> UIImage {
        let key = "\(profile.id)-\(profile.colorIndex)-\(profile.name)-\(profile.maxFSK)-\(profile.littleKid)-\(profile.avatar ?? "")"
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: AvatarView(profile: profile, size: 30))
        renderer.scale = 3
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
        cache[key] = image
        return image
    }
}

// MARK: - Bewertungen mit Links (Details)

/// Jede Bewertung ist ein Link zur Quelle: IMDb, Rotten Tomatoes, Metacritic, Letterboxd.
struct ScoreLinks: View {
    let film: Film

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if let imdb = film.imdbRating {
                        pill(url: "https://www.imdb.com/title/\(film.imdbID)/") {
                            Text("IMDb")
                                .font(.system(size: 10, weight: .black)).foregroundStyle(.black)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color(red: 0.96, green: 0.77, blue: 0.09), in: .rect(cornerRadius: 3))
                            Text(imdb, format: .number.precision(.fractionLength(1)))
                        }
                    }
                    if let rt = film.rottenTomatoes {
                        pill(url: "https://www.rottentomatoes.com/search?search=\(query)") {
                            Text(rt >= 60 ? "🍅" : "🤢")
                            Text("\(rt) %")
                        }
                    }
                    if let mc = film.metascore {
                        pill(url: "https://www.metacritic.com/search/\(query)/") {
                            Text("\(mc)")
                                .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 22, height: 20)
                                .background(mc >= 61 ? Color(red: 0.4, green: 0.8, blue: 0.2) : mc >= 40 ? .yellow : .red, in: .rect(cornerRadius: 3))
                            Text("Metacritic")
                        }
                    }
                    pill(url: "https://letterboxd.com/imdb/\(film.imdbID)/") {
                        HStack(spacing: 2) {
                            Circle().fill(.orange).frame(width: 7)
                            Circle().fill(.green).frame(width: 7)
                            Circle().fill(.blue).frame(width: 7)
                        }
                        Text("Letterboxd")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
        // Gedrückte Glas-Pillen wachsen leicht, nicht oben/unten abschneiden.
        .scrollClipDisabled()
        .padding(.vertical, -6)
        .padding(.horizontal, -20)
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
    }

    private var query: String {
        film.originalTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? film.originalTitle
    }

    private func pill<Content: View>(url: String, @ViewBuilder content: () -> Content) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                content()
                Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 36)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - Umbrechendes Layout (Chips)

/// Legt Elemente nebeneinander und bricht in die nächste Zeile um, wenn der Platz ausgeht.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
