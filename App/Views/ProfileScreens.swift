import SwiftUI

// MARK: - Avatare

/// Profilbilder nach Genres sortiert – wie die Avatar-Reihen bei Netflix, nur ohne fremde Figuren.
struct AvatarArt: Identifiable, Hashable {
    let id: String
    let emoji: String
    let category: String
    let colorIndex: Int

    var color: Color { Profile.palette[colorIndex % Profile.palette.count] }

    static let categories: [(name: String, key: String, color: Int, emojis: [String])] = [
        ("Science-Fiction", "scifi", 1, ["👽", "🤖", "🚀", "🪐", "👾", "🛸"]),
        ("Fantasy", "fantasy", 2, ["🐉", "🧙", "🦄", "🧚", "🧜", "🔮"]),
        ("Grusel", "grusel", 4, ["👻", "🧛", "🎃", "💀", "🕷️", "🧟"]),
        ("Abenteuer", "abenteuer", 0, ["🦖", "🏴‍☠️", "🦁", "🦈", "🦅", "🐺"]),
        ("Komödie", "komoedie", 5, ["🤡", "🐵", "🦆", "🐸", "🐧", "🦥"]),
        ("Für Kinder", "kinder", 3, ["🐻", "🐼", "🐰", "🦊", "🐨", "🐯"]),
    ]

    static let all: [AvatarArt] = categories.flatMap { c in
        c.emojis.enumerated().map { AvatarArt(id: "\(c.key)-\($0.offset)", emoji: $0.element, category: c.name, colorIndex: c.color) }
    }
    static func byID(_ id: String) -> AvatarArt? { all.first { $0.id == id } }
    static func inCategory(_ name: String) -> [AvatarArt] { all.filter { $0.category == name } }
}

/// Avatar als Kachel: Genre-Farbe, Figur in der Mitte.
struct AvatarTile: View {
    let art: AvatarArt?
    var initial = "?"
    var color: Color = Profile.palette[0]
    var size: CGFloat
    var circle = false

    var body: some View {
        let tint = art?.color ?? color
        let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        ZStack {
            LinearGradient(colors: [tint.mix(with: .black, by: 0.15), tint.mix(with: .black, by: 0.4)],
                           startPoint: .top, endPoint: .bottom)
            if let art {
                Text(art.emoji)
                    .font(.system(size: size * 0.56))
                    .shadow(color: .black.opacity(0.35), radius: size * 0.04, y: size * 0.03)
            } else {
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.14), lineWidth: max(0.5, size * 0.008)))
        .accessibilityHidden(true)
    }
}

// MARK: - Profil erstellen

/// Profil anlegen wie bei den großen Streamingdiensten: großes Profilbild im Mittelpunkt,
/// Name darunter, Kinderprofil als eigene Karte.
struct ProfileEditor: View {
    var isFirst: Bool
    var next: (_ name: String, _ avatar: AvatarArt, _ maxFSK: Int) -> Void

    @State private var name = ""
    @State private var art = AvatarArt.all.randomElement()!
    @State private var kid = false
    @State private var fsk = 6
    @State private var picking = false
    @FocusState private var focused: Bool

    private var quickPicks: [AvatarArt] {
        // Eine Figur je Genre, die gewählte immer vorne dabei.
        let firsts = AvatarArt.categories.map { AvatarArt.byID("\($0.key)-0")! }
        return [art] + (firsts + AvatarArt.categories.map { AvatarArt.byID("\($0.key)-1")! }).filter { $0 != art }.prefix(9)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 6) {
                        Text(isFirst ? "Dein Profil" : "Neues Profil")
                            .font(.largeTitle.weight(.heavy))
                        Text("Jedes Profil lernt seinen eigenen Geschmack.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)

                    Button { picking = true } label: {
                        AvatarTile(art: art, size: 168)
                            .id(art.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                    removal: .opacity))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil")
                                    .font(.headline)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive(), in: .circle)
                                    .offset(x: 10, y: 10)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profilbild ändern")

                    quickStrip

                    TextField("", text: $name, prompt: Text("Name").foregroundStyle(.white.opacity(0.35)))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { focused = false }
                        .padding(.vertical, 16)
                        .glassEffect(in: .capsule)
                        .padding(.horizontal, 24)

                    kidCard.padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: submit) {
                Text("Weiter").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(trimmed.isEmpty)
            .padding(.horizontal, 24).padding(.bottom, 8)
        }
        .sheet(isPresented: $picking) {
            AvatarPicker(selection: $art)
        }
        .sensoryFeedback(.selection, trigger: art)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private var quickStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(quickPicks) { a in
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { art = a } } label: {
                        AvatarTile(art: a, size: 56)
                            .overlay(RoundedRectangle(cornerRadius: 56 * 0.24, style: .continuous)
                                .stroke(.white, lineWidth: a == art ? 2.5 : 0).padding(-4))
                            .scaleEffect(a == art ? 1 : 0.9)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profilbild \(a.emoji)")
                }
                Button { picking = true } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 56 * 0.24))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Alle Profilbilder")
            }
            .padding(.horizontal, 24).padding(.vertical, 6)
        }
    }

    private var kidCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $kid.animation(.smooth)) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.and.child.holdinghands")
                        .font(.title3).foregroundStyle(.secondary)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kinderprofil").font(.headline)
                        Text("Nur altersgerechte Filme und Serien").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.green)
            if kid {
                HStack(spacing: 8) {
                    ForEach([0, 6, 12, 16], id: \.self) { value in
                        Button { withAnimation(.snappy) { fsk = value } } label: {
                            Text("FSK \(value)")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(fsk == value ? .black : .white)
                                .background(fsk == value ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Vorschläge, Suche und Katalog zeigen nur Titel bis FSK \(fsk) – auch wenn das Profil mit anderen zusammen schaut.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .glassEffect(in: .rect(cornerRadius: 26))
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        // Erst die Tastatur wegnehmen, dann weiter – sonst springt der nächste Schritt.
        focused = false
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            next(trimmed, art, kid ? fsk : 18)
        }
    }
}

/// Alle Profilbilder, nach Genre in Reihen – die Galerie, aus der man sich „seine Figur“ aussucht.
struct AvatarPicker: View {
    @Binding var selection: AvatarArt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(AvatarArt.categories, id: \.key) { c in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(c.name).font(.title3.weight(.bold)).padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(AvatarArt.inCategory(c.name)) { a in
                                        Button {
                                            selection = a
                                            dismiss()
                                        } label: {
                                            AvatarTile(art: a, size: 96)
                                                .overlay(RoundedRectangle(cornerRadius: 96 * 0.24, style: .continuous)
                                                    .stroke(.white, lineWidth: a == selection ? 3 : 0).padding(-5))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(c.name): \(a.emoji)")
                                    }
                                }
                                .padding(.horizontal, 20).padding(.vertical, 6)
                            }
                            .scrollClipDisabled()
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Profilbild wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", systemImage: "xmark") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Wer schaut?

/// Startbildschirm bei mehreren Profilen. Mehrere antippen = zusammen schauen.
struct WhoIsWatchingView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: [UUID] = []
    @State private var adding = false
    @State private var appeared = false

    var body: some View {
        let plan = store.subscription?.plan
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 6) {
                        Text("Wer schaut?").font(.largeTitle.weight(.heavy))
                        Text(plan?.allowsTogether == false ? "Wähle dein Profil." : "Mehrere antippen, um zusammen zu schauen.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 48)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 22)], spacing: 26) {
                        ForEach(Array(store.profiles.enumerated()), id: \.element.id) { i, profile in
                            tile(profile)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 16)
                                .animation(.smooth(duration: 0.5).delay(Double(i) * 0.06), value: appeared)
                        }
                        if store.canAddProfile {
                            Button { adding = true } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 34, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, height: 120)
                                        .overlay(RoundedRectangle(cornerRadius: 120 * 0.24, style: .continuous)
                                            .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                                    Text("Profil hinzufügen").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { withAnimation(.smooth) { store.chooseViewers(selected) } } label: {
                Text(buttonTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(selected.isEmpty)
            .padding(.horizontal, 24).padding(.bottom, 8)
        }
        .fullScreenCover(isPresented: $adding) {
            OnboardingFlow(mode: .addProfile, cancel: { adding = false }) { id in
                selected = [id]
                adding = false
            }
        }
        .onAppear {
            if selected.isEmpty { selected = Array(store.activeProfileIDs.prefix(1)) }
            if selected.isEmpty, let first = store.profiles.first { selected = [first.id] }
            appeared = true
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var buttonTitle: String {
        let names = store.profiles.filter { selected.contains($0.id) }.map(\.name)
        switch names.count {
        case 0: return "Profil wählen"
        case 1: return "Los geht's, \(names[0])"
        default: return "Zusammen schauen (\(names.count))"
        }
    }

    private func tile(_ profile: Profile) -> some View {
        let on = selected.contains(profile.id)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if store.subscription?.plan.allowsTogether == false {
                    selected = [profile.id]
                } else if on {
                    selected.removeAll { $0 == profile.id }
                } else {
                    selected.append(profile.id)
                }
            }
        } label: {
            VStack(spacing: 10) {
                AvatarTile(art: profile.avatarArt, initial: profile.initial, color: profile.color, size: 120)
                    .overlay(RoundedRectangle(cornerRadius: 120 * 0.24, style: .continuous)
                        .stroke(.white, lineWidth: on ? 3 : 0).padding(-5))
                    .overlay(alignment: .topTrailing) {
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2).symbolRenderingMode(.palette)
                                .foregroundStyle(.black, .white)
                                .offset(x: 10, y: -10)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if profile.isKid {
                            Text("Kinder").font(.caption2.weight(.heavy))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: .capsule)
                                .padding(8)
                        }
                    }
                    .scaleEffect(on ? 1.04 : 1)
                    .saturation(on || selected.isEmpty ? 1 : 0.55)
                    .opacity(on || selected.isEmpty ? 1 : 0.7)
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(on ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
