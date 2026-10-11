import SwiftUI

enum SwipeDirection: CaseIterable, Hashable {
    case left, right, up, down
}

struct SwipeOption {
    var title: String
    var symbol: String
    var color: Color
    /// false = Karte federt zurück (z. B. „Details“ öffnet nur ein Sheet).
    var flyOut = true
}

/// Stapel aus bis zu drei Karten. Jede Karte behält ihre Identität, während sie nach
/// vorne rückt – dadurch animiert der Stapel flüssig statt Views neu zu erzeugen.
/// Beim Loslassen wird der Swipe sofort gemeldet: Die nächste Karte rückt nach und der
/// Hintergrund wechselt, *während* die alte Karte noch wegfliegt.
struct SwipeDeck<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let options: [SwipeDirection: SwipeOption]
    @Binding var trigger: SwipeDirection?
    let onCommit: (Item, SwipeDirection) -> Void
    var onTap: (Item) -> Void = { _ in }
    @ViewBuilder let card: (Item, _ isTop: Bool) -> Card

    @State private var progress: CGFloat = 0
    /// Karten, die gerade wegfliegen – sie sind schon aus `items` raus, bleiben aber sichtbar.
    @State private var departing: [Item] = []

    private struct Entry: Identifiable {
        let item: Item
        let index: Int        // Position im Stapel; -1 = fliegt weg
        var id: Item.ID { item.id }
    }

    var body: some View {
        let leaving = Set(departing.map(\.id))
        let stack = items.filter { !leaving.contains($0.id) }.prefix(3)
        let entries = departing.map { Entry(item: $0, index: -1) }
            + stack.enumerated().map { Entry(item: $0.element, index: $0.offset) }
        ZStack {
            ForEach(entries.reversed()) { entry in
                let index = entry.index
                let item = entry.item
                SwipeCard(
                    options: options,
                    trigger: index == 0 ? $trigger : .constant(nil),
                    isActive: index == 0,
                    isDeparting: index == -1,
                    onProgress: { if index == 0 { progress = $0 } },
                    onCommit: { direction, flight in
                        guard options[direction]?.flyOut != false else {
                            onCommit(item, direction); return
                        }
                        departing.append(item)
                        // Nachrücken läuft parallel zum Wegfliegen.
                        withAnimation(.smooth(duration: max(flight, 0.32))) {
                            progress = 0
                            onCommit(item, direction)
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(flight + 0.05))
                            departing.removeAll { $0.id == item.id }
                        }
                    },
                    onTap: { onTap(item) }
                ) {
                    card(item, index <= 0)
                }
                .scaleEffect(scale(for: index))
                .offset(y: yOffset(for: index))
                .opacity(opacity(for: index))
                .zIndex(index == -1 ? 100 : Double(10 - index))
                .allowsHitTesting(index == 0)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)), removal: .identity))
            }
        }
    }

    // Hintere Karten rücken anteilig zum Ziehfortschritt der vorderen nach vorne.
    private func lift(_ index: Int) -> CGFloat { max(CGFloat(index) - min(progress, 1), 0) }
    private func scale(for index: Int) -> CGFloat { index <= 0 ? 1 : 1 - lift(index) * 0.06 }
    private func yOffset(for index: Int) -> CGFloat { index <= 0 ? 0 : lift(index) * 18 }
    private func opacity(for index: Int) -> Double { index <= 0 ? 1 : Double(1 - lift(index) * 0.4) }
}

/// Karte, die in vier Richtungen gewischt werden kann. Beim Ziehen färbt sie sich
/// stufenlos ein und zeigt, was beim Loslassen passiert. Unterhalb der Schwelle federt
/// sie zurück; ein schneller Wisch („Flick“) reicht auch ohne die Schwelle zu erreichen.
struct SwipeCard<Content: View>: View {
    let options: [SwipeDirection: SwipeOption]
    /// Von außen ausgelöster Swipe (Buttons unter der Karte).
    @Binding var trigger: SwipeDirection?
    var isActive = true
    var isDeparting = false
    var onProgress: (CGFloat) -> Void = { _ in }
    /// Richtung und Flugdauer (0 bei Richtungen ohne Abflug).
    let onCommit: (SwipeDirection, Double) -> Void
    var onTap: () -> Void = {}
    @ViewBuilder let content: () -> Content

    @State private var offset: CGSize = .zero
    @State private var armed = false
    @State private var flying = false

    private let threshold: CGFloat = 110

    private func direction(for offset: CGSize) -> SwipeDirection? {
        guard abs(offset.width) > 1 || abs(offset.height) > 1 else { return nil }
        if abs(offset.width) > abs(offset.height) {
            return offset.width > 0 ? .right : .left
        }
        return offset.height > 0 ? .down : .up
    }

    private func distance(_ offset: CGSize, _ d: SwipeDirection) -> CGFloat {
        (d == .left || d == .right) ? abs(offset.width) : abs(offset.height)
    }

    private var direction: SwipeDirection? { direction(for: offset) }

    private var progress: CGFloat {
        guard let direction else { return 0 }
        return min(distance(offset, direction) / threshold, 1.4)
    }

    /// Stufenlose Stärke je Richtung: Anteil der Bewegung in diese Richtung × Dominanz.
    /// Dadurch blenden die Farben beim Wechsel der Richtung weich ineinander.
    private func strength(_ d: SwipeDirection) -> CGFloat {
        let w = offset.width, h = offset.height
        let along: CGFloat = switch d {
        case .right: max(w, 0)
        case .left: max(-w, 0)
        case .down: max(h, 0)
        case .up: max(-h, 0)
        }
        let total = w * w + h * h
        guard total > 1 else { return 0 }
        let dominance = pow(along * along / total, 2)
        return min(along / threshold, 1) * dominance
    }

    /// Wie weit die nächste Karte schon nachrückt – stufenlos über alle Richtungen mit
    /// Abflug. „Details“ (nach oben) zählt nicht, die Karte bleibt dort ja liegen.
    private var lift: CGFloat {
        let total = SwipeDirection.allCases
            .filter { options[$0]?.flyOut == true }
            .map { strength($0) }
            .reduce(0, +)
        return min(total, 1)
    }

    var body: some View {
        content()
            .overlay {
                if isActive || isDeparting {
                    ZStack {
                        ForEach(SwipeDirection.allCases, id: \.self) { d in
                            if let option = options[d] { tint(option, strength(d), armed: armed && direction == d) }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 22)), anchor: .bottom)
            .gesture(drag, isEnabled: isActive && !isDeparting)
            .onTapGesture { if isActive && !flying { onTap() } }
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new }
            .animation(.smooth(duration: 0.2), value: armed)
            .onChange(of: trigger) { _, new in
                guard isActive, let new else { return }
                trigger = nil
                commit(new, velocity: .zero)
            }
    }

    private func tint(_ option: SwipeOption, _ s: CGFloat, armed: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(option.color.opacity(s * 0.5))
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(option.color.opacity(armed ? 1 : 0), lineWidth: 4)
            VStack(spacing: 10) {
                Image(systemName: option.symbol)
                    .font(.system(size: 34, weight: .bold))
                    .symbolEffect(.bounce, value: armed)
                    .frame(width: 76, height: 76)
                    .background(option.color.gradient, in: .circle)
                Text(option.title)
                    .font(.title2.weight(.heavy))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 10)
            .scaleEffect(armed ? 1.08 : 0.75 + 0.25 * s)
            .opacity(Double(min(s * 1.4, 1)))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !flying else { return }
                offset = resisted(value.translation)
                armed = progress >= 1 && options[direction ?? .up] != nil && direction != nil
                onProgress(lift)
            }
            .onEnded { value in
                guard !flying else { return }
                // Flick: die vorhergesagte Endposition zählt mit.
                let predicted = value.predictedEndTranslation
                let flickDir = direction(for: predicted)
                if armed, let direction {
                    commit(direction, velocity: value.velocity)
                } else if let flickDir, flickDir == direction, distance(predicted, flickDir) > threshold * 2.2,
                          options[flickDir]?.flyOut == true {
                    commit(flickDir, velocity: value.velocity)
                } else {
                    withAnimation(Self.settle) { offset = .zero; onProgress(0) }
                }
                armed = false
            }
    }

    /// Vertikale Richtungen ohne Abflug („Details“) bekommen Gummiband-Widerstand –
    /// nur vertikal. Seitwärts bleibt die Karte frei beweglich.
    private func resisted(_ t: CGSize) -> CGSize {
        let d: SwipeDirection = t.height < 0 ? .up : .down
        guard t.height != 0, options[d]?.flyOut == false else { return t }
        let limit = threshold * 1.4
        let sign: CGFloat = t.height < 0 ? -1 : 1
        return CGSize(width: t.width, height: sign * limit * (1 - exp(-abs(t.height) / limit)))
    }

    private func commit(_ direction: SwipeDirection, velocity: CGSize) {
        guard let option = options[direction] else { return }
        guard option.flyOut else {
            withAnimation(Self.settle) { offset = .zero; onProgress(0) }
            onCommit(direction, 0)
            return
        }
        flying = true
        // Gerade Linie: die Karte fliegt weiter in die Richtung, in die sie schon zeigt –
        // man sieht vorher, wo sie landet. Ohne Ziehweg (Buttons) geht es entlang der Achse.
        let axis: CGVector = switch direction {
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        case .up: CGVector(dx: 0, dy: -1)
        case .down: CGVector(dx: 0, dy: 1)
        }
        let length = hypot(offset.width, offset.height)
        var dir = length > 30 ? CGVector(dx: offset.width / length, dy: offset.height / length) : axis
        // Nie mehr als ~40° von der gewählten Achse abweichen.
        if dir.dx * axis.dx + dir.dy * axis.dy < 0.75 { dir = axis }
        let travel: CGFloat = 1100
        let target = CGSize(width: offset.width + dir.dx * travel, height: offset.height + dir.dy * travel)
        // Schwung aus der Geste übernehmen: schneller Wisch = schneller Abflug.
        let speed = max(hypot(velocity.width, velocity.height), 1000)
        let duration = Double(min(max(travel / speed, 0.28), 0.42))
        // Linear, damit Tempo und Richtung beim Loslassen erhalten bleiben.
        withAnimation(.linear(duration: duration)) { offset = target }
        onCommit(direction, duration)
    }

    private static var settle: Animation { .spring(duration: 0.35, bounce: 0.1) }
}

/// Kleine Legende unter der Karte – erklärt die vier Richtungen.
struct SwipeLegend: View {
    let options: [SwipeDirection: SwipeOption]
    var body: some View {
        HStack(spacing: 14) {
            item(.left, arrow: "arrow.left")
            item(.down, arrow: "arrow.down")
            item(.up, arrow: "arrow.up")
            item(.right, arrow: "arrow.right")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private func item(_ d: SwipeDirection, arrow: String) -> some View {
        if let o = options[d] {
            HStack(spacing: 3) {
                Image(systemName: arrow).foregroundStyle(o.color)
                Text(o.title)
            }
        }
    }
}
