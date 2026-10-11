import SwiftUI

// MARK: - Avatare

/// Profilbilder nach Genres sortiert, wie die Avatar-Reihen bei Netflix, nur ohne fremde Figuren.
/// Jede Figur hat ihre eigene Farbe, sie wird zur Akzentfarbe des Profils.
struct AvatarArt: Identifiable, Hashable {
    let id: String
    let emoji: String
    let category: String
    let colorIndex: Int
    let hex: UInt32

    var color: Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Neue Figuren nur hinten anhängen: Die Nummer in der ID verweist auf gespeicherte Profile.
    static let categories: [(name: String, key: String, color: Int, emojis: [(String, UInt32)])] = [
        ("Science-Fiction", "scifi", 1, [("👽", 0x7ED957), ("🤖", 0x8FA8C8), ("🚀", 0xFF5A4E), ("🪐", 0xF2B25C),
                                         ("👾", 0xA779FF), ("🛸", 0x4FD1C5), ("🌌", 0x6C7BFF), ("☄️", 0xFF8A3D),
                                         ("🛰️", 0x7CC4E8), ("🌙", 0xF5D76E)]),
        ("Fantasy", "fantasy", 2, [("🐉", 0x3FBF7F), ("🧙", 0x8E6CFF), ("🦄", 0xFF8AD8), ("🧚", 0x6FE0C8),
                                   ("🧜", 0x3BC4E0), ("🔮", 0xB57BFF), ("🏰", 0xC2A878), ("🍄", 0xFF5F57),
                                   ("🗝️", 0xE8B04B), ("🌈", 0xFFB547)]),
        ("Grusel", "grusel", 4, [("👻", 0xB8C4D6), ("🧛", 0xE0384F), ("🎃", 0xFF8C2B), ("💀", 0xD9D2C3),
                                 ("🕷️", 0x7A5BD6), ("🧟", 0x8DBF4A), ("🦇", 0x9B59B6), ("🕯️", 0xF7C35C),
                                 ("🦉", 0xB08B5E), ("🌑", 0x7D8BA6)]),
        ("Abenteuer", "abenteuer", 0, [("🦖", 0x59C36A), ("🏴‍☠️", 0x9AA3AE), ("🦁", 0xF5A623), ("🦈", 0x4A90E2),
                                       ("🦅", 0xC8894A), ("🐺", 0x8796A8), ("🧭", 0xE9A23B), ("🌋", 0xFF6A3D),
                                       ("🏔️", 0x8EC9FF), ("🐊", 0x6BAF5A)]),
        ("Komödie", "komoedie", 5, [("🤡", 0xFF4D5E), ("🐵", 0xC68B59), ("🦆", 0xFFD23F), ("🐸", 0x6DD36D),
                                    ("🐧", 0x7FB8FF), ("🦥", 0xC9A27E), ("🍌", 0xFFE066), ("🦩", 0xFF7EB6),
                                    ("🐙", 0xFF7A6B), ("🤠", 0xE0A458)]),
        ("Kino-Snacks", "snacks", 5, [("🍿", 0xF4D35E), ("🍕", 0xFF9F43), ("🍩", 0xFF7EB6), ("🌮", 0xF7B267),
                                      ("🧁", 0xE58FD6), ("🍉", 0xFF5E6C), ("🥨", 0xC8894A), ("🍫", 0xB07A55)]),
        ("Für Kinder", "kinder", 3, [("🐻", 0xC98A5A), ("🐼", 0x7BDCB5), ("🐰", 0xFFA3C7), ("🦊", 0xFF8A3D),
                                     ("🐨", 0x9DB4D3), ("🐯", 0xFFB13D), ("🐶", 0xE3B27A), ("🐱", 0xFFC86B),
                                     ("🐷", 0xFF9EB5), ("🐥", 0xFFD84D), ("🐳", 0x5AB0FF), ("🦋", 0x6FA8FF)]),
    ]

    static let all: [AvatarArt] = categories.flatMap { c in
        c.emojis.enumerated().map {
            AvatarArt(id: "\(c.key)-\($0.offset)", emoji: $0.element.0, category: c.name, colorIndex: c.color, hex: $0.element.1)
        }
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
    /// Vorhandenes Profil bearbeiten statt ein neues anlegen.
    var editing: Profile? = nil
    /// Abbrechen-Knopf oben links (nur, wo man auch zurück kann).
    var cancel: (() -> Void)? = nil
    /// Löschen-Knopf unten (nur beim Bearbeiten).
    var delete: (() -> Void)? = nil
    /// Profil wird gerade erst angelegt (Zurück aus der Filmauswahl): „Weiter“ statt „Sichern“.
    var continuing = false
    var next: (_ name: String, _ avatar: AvatarArt, _ maxFSK: Int, _ littleKid: Bool) -> Void

    @State private var name = ""
    @State private var art = AvatarArt.all.randomElement()!
    @State private var kid = false
    @State private var fsk = 6
    @State private var little = false
    @State private var picking = false
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    init(isFirst: Bool, editing: Profile? = nil, continuing: Bool = false, cancel: (() -> Void)? = nil, delete: (() -> Void)? = nil,
         next: @escaping (_ name: String, _ avatar: AvatarArt, _ maxFSK: Int, _ littleKid: Bool) -> Void) {
        self.isFirst = isFirst; self.editing = editing; self.continuing = continuing
        self.cancel = cancel; self.delete = delete; self.next = next
        if let p = editing {
            _name = State(initialValue: p.name)
            _art = State(initialValue: p.avatarArt ?? AvatarArt.all[p.colorIndex % AvatarArt.all.count])
            _kid = State(initialValue: p.maxFSK < 18)
            _fsk = State(initialValue: p.maxFSK < 18 ? p.maxFSK : 6)
            _little = State(initialValue: p.littleKid)
        }
    }

    /// Feste Reihe zum Durchtippen: Sie sortiert sich beim Antippen nicht um,
    /// sonst verschwindet die Figur, die gerade noch vorne stand.
    @State private var quickPicks: [AvatarArt] = []

    private static func makeQuickPicks(including art: AvatarArt) -> [AvatarArt] {
        let picks = (0..<2).flatMap { i in AvatarArt.categories.compactMap { AvatarArt.byID("\($0.key)-\(i)") } }
        return picks.contains(art) ? picks : [art] + picks
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 6) {
                        Text(editing != nil && !continuing ? "Profil bearbeiten" : isFirst ? "Dein Profil" : "Neues Profil")
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

                    if let delete {
                        Button("Profil löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .font(.headline)
                            .confirmationDialog("„\(editing?.name ?? name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("Profil löschen", role: .destructive, action: delete)
                            } message: {
                                Text("Merkliste, Bewertungen und der gelernte Geschmack dieses Profils gehen verloren.")
                            }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topLeading) {
            if let cancel {
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Abbrechen")
                .padding(.leading, 20).padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: submit) {
                Text(editing != nil && !continuing ? "Sichern" : "Weiter").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
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
        .onAppear { if quickPicks.isEmpty { quickPicks = Self.makeQuickPicks(including: art) } }
        .onChange(of: art) { _, new in
            // Aus der großen Auswahl: vorne einreihen, ohne eine andere Figur zu verdrängen.
            if !quickPicks.contains(new) { withAnimation(.snappy) { quickPicks.insert(new, at: 0) } }
        }
        .sensoryFeedback(.selection, trigger: art)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private var quickStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(quickPicks.isEmpty ? Self.makeQuickPicks(including: art) : quickPicks) { a in
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
                // „Bis 5“ ist FSK 0 plus nur Kinder- und Familientitel.
                HStack(spacing: 8) {
                    ForEach([(-1, "Bis 5 J."), (6, "FSK 6"), (12, "FSK 12"), (16, "FSK 16")], id: \.0) { value, label in
                        let on = value == -1 ? little : (!little && fsk == value)
                        Button {
                            withAnimation(.snappy) {
                                little = value == -1
                                fsk = max(value, 0)
                            }
                        } label: {
                            Text(label)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(on ? .black : .white)
                                .background(on ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(little
                     ? "Nur Zeichentrick- und Familientitel ohne Altersgrenze. Statt zu wischen, suchst du gleich die Lieblingsfilme deines Kindes aus."
                     : "Vorschläge, Suche und Katalog zeigen nur Titel bis FSK \(fsk), auch wenn das Profil mit anderen zusammen schaut.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .glassEffect(in: .rect(cornerRadius: 26))
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        // Erst die Tastatur wegnehmen, dann weiter, sonst springt der nächste Schritt.
        focused = false
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            next(trimmed, art, kid ? fsk : 18, kid && little)
        }
    }
}

// MARK: - Profile verwalten

/// Alle Profile des Haushalts: umbenennen, Bild und Altersstufe ändern, löschen.
/// Hier liegt auch der Import von Letterboxd und IMDb, bewusst nicht im Onboarding.
struct ManageProfilesView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: UUID?
    @State private var adding = false
    @State private var importing: UUID?
    @State private var confirmDelete: Profile?

    /// Importieren ergibt nur bei Erwachsenen Sinn, Kinder haben kein Letterboxd.
    private var importable: [Profile] { store.profiles.filter { !$0.isKid } }

    var body: some View {
        List {
            Section {
                ForEach(store.profiles) { profile in
                    Button { editing = profile.id } label: {
                        HStack(spacing: 14) {
                            AvatarView(profile: profile, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).font(.headline)
                                Text(profile.ageLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if store.canDeleteProfile {
                            Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = profile }
                        }
                    }
                }
                Button("Profil hinzufügen", systemImage: "person.badge.plus") { adding = true }
            } footer: {
                Text(store.canDeleteProfile ? "Zum Löschen nach links wischen oder das Profil öffnen." : "Das letzte Profil kann nicht gelöscht werden.")
            }

            if !importable.isEmpty {
                Section {
                    if importable.count == 1, let only = importable.first {
                        Button("Von Letterboxd oder IMDb importieren", systemImage: "square.and.arrow.down") { importing = only.id }
                    } else {
                        Menu {
                            ForEach(importable) { p in Button(p.name) { importing = p.id } }
                        } label: {
                            Label("Von Letterboxd oder IMDb importieren", systemImage: "square.and.arrow.down")
                        }
                    }
                } header: {
                    Text("Bewertungen mitbringen")
                } footer: {
                    Text("Wer schon Filme bewertet hat, kann den Daten-Export (ratings.csv) laden. Die Vorschläge werden dadurch genauer.")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { editing.map(IdentifiedUUID.init) }, set: { editing = $0?.id })) { item in
            if let profile = store.profiles.first(where: { $0.id == item.id }) {
                ProfileEditor(isFirst: false, editing: profile, cancel: { editing = nil },
                              delete: store.canDeleteProfile ? { store.deleteProfile(profile.id); editing = nil } : nil) { name, art, fsk, little in
                    store.editProfile(profile.id, name: name, avatar: art, maxFSK: fsk, littleKid: little)
                    editing = nil
                }
                .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(isPresented: $adding) {
            OnboardingFlow(mode: .addProfile, cancel: { adding = false }) { _ in adding = false }
        }
        .sheet(item: Binding(get: { importing.map(IdentifiedUUID.init) }, set: { importing = $0?.id })) { item in
            ImportStep(profileID: item.id) { importing = nil }
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("„\(confirmDelete?.name ?? "")“ löschen?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Profil löschen", role: .destructive) {
                if let p = confirmDelete { withAnimation { store.deleteProfile(p.id) } }
                confirmDelete = nil
            }
        } message: {
            Text("Merkliste, Bewertungen und der gelernte Geschmack dieses Profils gehen verloren.")
        }
    }
}

/// Alle Profilbilder, nach Genre in Reihen, die Galerie, aus der man sich „seine Figur“ aussucht.
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
