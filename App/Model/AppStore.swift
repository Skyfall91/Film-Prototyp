import SwiftUI

/// Ein Film, der geschaut wurde und noch bewertet werden soll („Wie war's gestern?“).
struct PendingRating: Codable, Hashable, Identifiable, Sendable {
    var filmID: String
    var profileIDs: [UUID]
    var date: Date
    var id: String { filmID + date.description }
}

enum SwipeAction: CaseIterable {
    case notToday, watchlist, alreadySeen, details

    var title: String {
        switch self {
        case .notToday: "Heute nicht"
        case .watchlist: "Merken"
        case .alreadySeen: "Schon gesehen"
        case .details: "Details"
        }
    }
    var symbol: String {
        switch self {
        case .notToday: "xmark"
        case .watchlist: "bookmark.fill"
        case .alreadySeen: "eye.fill"
        case .details: "info"
        }
    }
    var color: Color {
        switch self {
        case .notToday: Color(red: 1, green: 0.27, blue: 0.3)
        case .watchlist: Color(red: 0.2, green: 0.85, blue: 0.5)
        case .alreadySeen: Color(red: 0.62, green: 0.45, blue: 1)
        case .details: Color(red: 0.3, green: 0.6, blue: 1)
        }
    }
}

enum AuthError: LocalizedError {
    case invalidEmail, weakPassword, noAccount, unknownEmail, wrongPassword, emailTaken, wrongCredentials, offline
    case server(String)

    var errorDescription: String? {
        switch self {
        case .wrongCredentials: "E-Mail oder Passwort stimmt nicht."
        case .offline: "Keine Verbindung zum Server. Ohne Netz geht nur ein Konto, das auf diesem Gerät schon angemeldet war."
        case .server(let message): "Der Server meldet: \(message)"
        case .emailTaken: "Zu dieser E-Mail gibt es schon ein Konto. Melde dich damit an."
        case .invalidEmail: "Das sieht nicht nach einer E-Mail-Adresse aus."
        case .weakPassword: "Das Passwort braucht mindestens 8 Zeichen und eine Zahl."
        case .noAccount: "Auf diesem Gerät gibt es noch kein Konto. Erstelle zuerst eins."
        case .unknownEmail: "Zu dieser E-Mail gibt es auf diesem Gerät kein Konto."
        case .wrongPassword: "Das Passwort stimmt nicht."
        }
    }

    static func looksLikeEmail(_ mail: String) -> Bool {
        let parts = mail.split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !mail.contains(" ")
    }
}

@Observable
final class AppStore {
    var profiles: [Profile] = []
    var activeProfileIDs: [UUID] = []
    /// Konto des Haushalts (Registrierung/Login), getrennt von den Profilen, die es enthält.
    var account: Account?
    var signedIn = false
    let purchases = PurchaseService()
    var onboardingDone = false
    var pendingRatings: [PendingRating] = []
    /// Zählt jede gespeicherte Änderung (Swipes, Chat, Kalibrierung), damit „Für dich“ sofort neu sortiert.
    private(set) var tasteRevision = 0
    /// Bewertung, die als Sheet angezeigt werden soll (nach dem Schauen).
    var ratingToPresent: PendingRating?
    /// Zählt Swipes auf der Startseite, die Gesten-Legende verschwindet nach ein paar Swipes.
    var homeSwipeCount = UserDefaults.standard.integer(forKey: "homeSwipeCount") {
        didSet { UserDefaults.standard.set(homeSwipeCount, forKey: "homeSwipeCount") }
    }

    // Sitzungszustand (nicht gespeichert)
    var skippedToday: Set<String> = []
    var runtimeFilter: RuntimeFilter? = nil
    var kindFilter: KindFilter = .all
    var hasChosenViewers = false
    /// Aktiver Tab (damit z. B. „Profile verwalten“ direkt zum Profil-Tab springt).
    var selectedTab = UserDefaults.standard.integer(forKey: "startTab")
    private var undoStack: [(profiles: [Profile], skipped: Set<String>, pending: [PendingRating])] = []

    var activeProfiles: [Profile] { profiles.filter { activeProfileIDs.contains($0.id) } }
    var accent: Color { Theme.accent(for: activeProfiles.first) }

    // MARK: - Konto & Abo

    var subscription: Subscription? { account?.subscription }
    /// Abspielen braucht ein aktives Abo (auch in der Testphase). Trailer sind frei.
    var canPlay: Bool { subscription?.isActive == true }
    var profileLimit: Int { subscription?.plan.maxProfiles ?? Plan.familie.maxProfiles }
    var canAddProfile: Bool { profiles.count < profileLimit }

    /// Neues Konto, online bei Supabase, damit es auf jedem Gerät klappt.
    /// Ohne Netz wird es erst nur auf diesem Gerät angelegt und beim nächsten Anmelden online nachgeholt.
    func register(email: String, password: String) async throws {
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard AuthError.looksLikeEmail(mail) else { throw AuthError.invalidEmail }
        guard password.count >= 8, password.contains(where: \.isNumber) else { throw AuthError.weakPassword }
        guard db.record(mail) == nil else { throw AuthError.emailTaken }
        var session: CloudAccounts.Session?
        do { session = try await CloudAccounts.signUp(email: mail, password: password) }
        catch CloudAccounts.CloudError.alreadyRegistered { throw AuthError.emailTaken }
        catch CloudAccounts.CloudError.offline { session = nil }
        catch CloudAccounts.CloudError.server(let message) { throw AuthError.server(message) }
        // Ein anderes Konto war geladen: Es liegt sicher in der Datenbank, das neue fängt leer an.
        if account != nil { pushNow(); clearSession() }
        cloudSession = session
        let salt = UUID().uuidString
        account = Account(email: mail, passwordHash: Account.hash(password, salt: salt), salt: salt,
                          created: .now, consented: .now, subscription: nil)
        signedIn = true
        save(signedInNow: true)
    }

    /// Anmelden online bei Supabase und den Stand dieses Kontos laden, auf jedem Gerät.
    /// Ohne Netz zählt das Konto, das schon auf diesem Gerät gespeichert ist.
    func signIn(email: String, password: String) async throws {
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let local = db.record(mail)
        let localMatches = local.map { Account.hash(password, salt: $0.salt) == $0.passwordHash } ?? false
        var session: CloudAccounts.Session?
        var remote: Snapshot?
        do {
            let s = try await CloudAccounts.signIn(email: mail, password: password)
            session = s
            if let data = try await CloudAccounts.loadState(s) { remote = try? JSONDecoder().decode(Snapshot.self, from: data) }
        } catch CloudAccounts.CloudError.invalidCredentials {
            // Konto aus der Zeit vor den Online-Konten, nur auf diesem Gerät: jetzt einmal online anlegen.
            guard localMatches else { throw AuthError.wrongCredentials }
            session = try? await CloudAccounts.signUp(email: mail, password: password)
        } catch CloudAccounts.CloudError.offline {
            guard local != nil else { throw AuthError.offline }
            guard localMatches else { throw AuthError.wrongPassword }
        } catch CloudAccounts.CloudError.server(let message) {
            throw AuthError.server(message)
        }
        if account?.email != mail { pushNow(); clearSession() }
        // Online-Stand zuerst, sonst der Stand auf diesem Gerät, sonst ein frisches Konto.
        if let remote {
            apply(remote)
        } else if account?.email != mail, let local, let snap = try? JSONDecoder().decode(Snapshot.self, from: local.state) {
            apply(snap)
        }
        if account?.email != mail {
            account = Account(email: mail, passwordHash: "", salt: "", created: .now, consented: .now, subscription: nil)
        }
        // Online liegt kein Passwort-Hash, für das Anmelden ohne Netz bekommt das Gerät einen eigenen.
        let salt = UUID().uuidString
        account?.salt = salt
        account?.passwordHash = Account.hash(password, salt: salt)
        cloudSession = session
        signedIn = true
        hasChosenViewers = profiles.count <= 1
        save(signedInNow: true)
    }

    /// E-Mails aller Konten auf diesem Gerät, zum schnellen Zurückwechseln beim Anmelden.
    var savedAccounts: [String] { db.emails }

    /// Gerade online angemeldet (sonst nur auf dem Gerät).
    var isOnline: Bool { cloudSession != nil }

    func signOut() {
        pushNow()
        cloudSession = nil
        CloudAccounts.signOut()
        signedIn = false
        hasChosenViewers = false
        skippedToday = []; undoStack = []
        save()
    }

    /// DSGVO: Konto samt aller Profile, Bewertungen und Importe löschen, online und auf dem Gerät.
    func deleteAccount() {
        if let session = cloudSession {
            Task {
                guard let s = await CloudAccounts.valid(session) else { return }
                try? await CloudAccounts.deleteAccount(s)
            }
        }
        cloudSession = nil
        if let email = account?.email { db.delete(email) }
        account = nil
        signedIn = false
        resetAll()
    }

    /// Profile und Sitzung leeren (beim Wechsel zu einem anderen Konto).
    private func clearSession() {
        profiles = []; activeProfileIDs = []; onboardingDone = false; pendingRatings = []
        skippedToday = []; undoStack = []; runtimeFilter = nil; kindFilter = .all; hasChosenViewers = false
    }

    func subscribe(_ sub: Subscription) {
        account?.subscription = sub
        // Weniger Profile im neuen Tarif: nichts löschen, nur nicht mehr gleichzeitig schauen.
        if !sub.plan.allowsTogether, activeProfileIDs.count > 1 { activeProfileIDs = Array(activeProfileIDs.prefix(1)) }
        save()
    }

    func setCanceled(_ canceled: Bool) {
        account?.subscription?.canceled = canceled
        save()
    }

    /// Abo mit dem App Store abgleichen (Kündigung oder Wechsel im Systemblatt).
    func syncSubscription() async {
        await purchases.load()
        guard purchases.storeKitAvailable, subscription?.source != .demo else { return }
        if let current = await purchases.currentSubscription() { account?.subscription = current; save() }
    }

    func chooseViewers(_ ids: [UUID]) {
        activeProfileIDs = profiles.map(\.id).filter(ids.contains)
        hasChosenViewers = true
        skippedToday = []
        save()
    }
    var canUndo: Bool { !undoStack.isEmpty }

    init() {
        load()
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") { seedDemo() }
        if let k = UserDefaults.standard.string(forKey: "kind").flatMap(KindFilter.init) { kindFilter = k }
    }

    /// Startparameter `-seedDemo`: ein fertiges Profil, für Pitch-Demos und Screenshots.
    func seedDemo() {
        cloudSession = nil
        resetAll()
        var demo = Profile(name: "Demo", colorIndex: 1, avatar: "scifi-0")
        for (id, i) in [("dune", Interaction.loved), ("interstellar", .loved), ("inception", .liked), ("the-batman", .liked),
                        ("barbie", .disliked), ("la-la-land", .disliked), ("parasite", .liked), ("mad-max-fury-road", .liked),
                        ("shrek", .unseen), ("joker", .liked), ("get-out", .liked), ("paddington-2", .disliked)] {
            if let f = FilmIndex.film(id) { demo.learn(f, i); demo.interactions[id] = i }
        }
        demo.progress["serie-dark"] = EpisodeRef(season: 1, episode: 4)
        profiles = [demo]
        let salt = "demo"
        account = Account(email: "demo@film.example", passwordHash: Account.hash("film-demo", salt: salt), salt: salt,
                          created: .now.addingTimeInterval(-40 * 86_400), consented: .now.addingTimeInterval(-40 * 86_400),
                          subscription: Subscription(plan: .familie, started: .now.addingTimeInterval(-40 * 86_400),
                                                     renews: .now.addingTimeInterval(20 * 86_400), trial: false, source: .demo))
        signedIn = true
        onboardingDone = true
        if DemoScreen.current == "who" { hasChosenViewers = false; activeProfileIDs = [demo.id]; save(); return }
        hasChosenViewers = true
        let args = ProcessInfo.processInfo.arguments
        activeProfileIDs = [demo.id]
        if args.contains("-pendingRating") {
            pendingRatings = [PendingRating(filmID: "dune-part-two", profileIDs: activeProfileIDs, date: .now.addingTimeInterval(-86_400))]
        }
        save()
    }

    // MARK: - Empfehlungen

    var recommendations: [Recommendation] { recommendations(limit: 3) }

    func recommendations(limit: Int) -> [Recommendation] {
        RecommendationEngine.recommendations(profiles: activeProfiles, runtime: runtimeFilter, kind: kindFilter,
                                            skipped: skippedToday, limit: limit)
    }

    func recommendation(for film: Film) -> Recommendation {
        let profs = activeProfiles
        return Recommendation(
            film: film,
            match: RecommendationEngine.matchPercent(RecommendationEngine.groupScore(film, profiles: profs)),
            reason: RecommendationEngine.reason(for: film, profiles: profs))
    }

    func apply(_ action: SwipeAction, to film: Film) {
        guard action != .details else { return }
        undoStack.append((profiles, skippedToday, pendingRatings))
        if undoStack.count > 20 { undoStack.removeFirst() }
        switch action {
        case .notToday:
            skippedToday.insert(film.id)
            record(film, .notToday, scale: 1 / Double(max(activeProfileIDs.count, 1)))
        case .watchlist:
            record(film, .watchlist)
            for id in activeProfileIDs { update(id) { if !$0.watchlist.contains(film.id) { $0.watchlist.insert(film.id, at: 0) } } }
        case .alreadySeen:
            record(film, .alreadySeen)
            pendingRatings.append(PendingRating(filmID: film.id, profileIDs: activeProfileIDs, date: .now))
        case .details: break
        }
        save()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        profiles = last.profiles
        skippedToday = last.skipped
        pendingRatings = last.pending
        save()
    }

    /// „Abspielen“: zählt für alle gerade schauenden Profile und erzeugt eine offene Bewertung.
    func play(_ film: Film, episode: EpisodeRef? = nil) {
        if film.isSeries {
            let ref = episode ?? nextEpisode(of: film) ?? film.firstEpisode
            let firstTime = activeProfiles.allSatisfy { $0.interactions[film.id] == nil }
            for id in activeProfileIDs {
                update(id) { p in
                    if let ref { p.progress[film.id] = film.episode(after: ref) ?? ref }
                    p.watchlist.removeAll { $0 == film.id }
                }
            }
            record(film, .played)
            // Bewertet wird die Serie einmal, nach der ersten Folge, nicht jede Folge.
            if firstTime { pendingRatings.append(PendingRating(filmID: film.id, profileIDs: activeProfileIDs, date: .now)) }
            save()
            return
        }
        record(film, .played)
        for id in activeProfileIDs { update(id) { $0.watchlist.removeAll { $0 == film.id } } }
        pendingRatings.removeAll { $0.filmID == film.id }
        pendingRatings.append(PendingRating(filmID: film.id, profileIDs: activeProfileIDs, date: .now))
        save()
    }

    func rate(_ pending: PendingRating, ratings: [UUID: Interaction], reviews: [UUID: String]) {
        guard let film = FilmIndex.film(pending.filmID) else { return }
        for (pid, rating) in ratings {
            update(pid) {
                $0.learn(film, rating)
                $0.interactions[film.id] = rating
                let text = reviews[pid]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                $0.reviews.removeAll { $0.filmID == film.id }
                $0.reviews.insert(Review(filmID: film.id, rating: rating, text: text, date: .now), at: 0)
            }
        }
        pendingRatings.removeAll { $0.id == pending.id }
        save()
    }

    func dismissRating(_ pending: PendingRating) {
        pendingRatings.removeAll { $0.id == pending.id }
        save()
    }

    func toggleWatchlist(_ film: Film) {
        let inList = activeProfiles.contains { $0.watchlist.contains(film.id) }
        for id in activeProfileIDs {
            update(id) {
                if inList { $0.watchlist.removeAll { $0 == film.id } }
                else if !$0.watchlist.contains(film.id) { $0.watchlist.insert(film.id, at: 0); $0.learn(film, .watchlist) }
            }
        }
        save()
    }

    /// Nächste Folge für die gerade schauenden Profile (das erste Profil mit Fortschritt zählt).
    func nextEpisode(of film: Film) -> EpisodeRef? {
        activeProfiles.lazy.compactMap { $0.progress[film.id] }.first
    }

    /// Folge, die „Abspielen“ startet: weiterschauen oder ganz vorne anfangen.
    func upNext(_ film: Film) -> EpisodeRef? {
        film.isSeries ? (nextEpisode(of: film) ?? film.firstEpisode) : nil
    }

    func playLabel(_ film: Film) -> String {
        guard let ref = upNext(film) else { return "Abspielen" }
        return nextEpisode(of: film) == nil ? "Ansehen · \(ref.short)" : "Weiterschauen · \(ref.short)"
    }

    /// Angefangene Serien der aktiven Profile, für „Weiterschauen“.
    var continueWatching: [(film: Film, next: EpisodeRef)] {
        var seen = Set<String>()
        return activeProfiles.flatMap { p in p.progress.map { ($0.key, $0.value) } }
            .compactMap { id, ref in
                guard seen.insert(id).inserted, let f = FilmIndex.film(id) else { return nil }
                return (f, ref)
            }
            .sorted { $0.film.title < $1.film.title }
    }

    func isOnWatchlist(_ film: Film) -> Bool { activeProfiles.contains { $0.watchlist.contains(film.id) } }

    var watchlist: [Film] {
        var seen = Set<String>()
        return activeProfiles.flatMap(\.watchlist).filter { seen.insert($0).inserted }.compactMap(FilmIndex.film)
    }

    private func record(_ film: Film, _ interaction: Interaction, scale: Double = 1) {
        for id in activeProfileIDs {
            update(id) {
                $0.learn(film, interaction, scale: scale)
                if interaction != .notToday { $0.interactions[film.id] = interaction }
            }
        }
    }

    // MARK: - Profile

    func update(_ id: UUID, _ change: (inout Profile) -> Void) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&profiles[i])
    }

    @discardableResult
    func addProfile(name: String, colorIndex: Int, maxFSK: Int = 18, littleKid: Bool = false, avatar: String? = nil) -> UUID {
        var p = Profile(name: name, colorIndex: colorIndex, maxFSK: maxFSK, avatar: avatar)
        p.littleKid = littleKid
        profiles.append(p)
        save()
        return p.id
    }

    /// Name, Bild und Altersstufe ändern, der gelernte Geschmack bleibt.
    func editProfile(_ id: UUID, name: String, avatar: AvatarArt, maxFSK: Int, littleKid: Bool) {
        update(id) {
            $0.name = name; $0.avatar = avatar.id; $0.colorIndex = avatar.colorIndex
            $0.maxFSK = maxFSK; $0.littleKid = littleKid
        }
        save()
    }

    /// Das letzte Profil bleibt, ohne Profil gäbe es niemanden, für den die App vorschlägt.
    var canDeleteProfile: Bool { profiles.count > 1 }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        activeProfileIDs.removeAll { $0 == id }
        if activeProfileIDs.isEmpty, let first = profiles.first { activeProfileIDs = [first.id] }
        save()
    }

    func calibrate(profile id: UUID, film: Film, _ interaction: Interaction) {
        update(id) {
            $0.learn(film, interaction)
            $0.interactions[film.id] = interaction
        }
        save()
    }

    func finishOnboarding(profile id: UUID) {
        onboardingDone = true
        activeProfileIDs = [id]
        hasChosenViewers = true
        save()
    }

    func resetAll() {
        profiles = []; activeProfileIDs = []; onboardingDone = false; pendingRatings = []
        if account == nil { signedIn = false }
        skippedToday = []; undoStack = []; runtimeFilter = nil; kindFilter = .all; hasChosenViewers = false
        save()
    }

    // MARK: - Persistenz
    // Der aktuelle Stand liegt als JSON-Datei vor (schneller Start), jedes Konto zusätzlich
    // in der Konten-Datenbank, damit man per Anmeldung zu ihm zurückkehren kann.

    private let db = AccountDatabase()
    /// Online-Sitzung des angemeldeten Kontos (nil = nur auf dem Gerät, z. B. ohne Netz oder im Demo-Modus).
    private var cloudSession: CloudAccounts.Session?
    private var pushTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var profiles: [Profile]
        var activeProfileIDs: [UUID]
        var onboardingDone: Bool
        var pendingRatings: [PendingRating]
        var account: Account?
        var signedIn: Bool?
    }

    private var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "state.json")
    }

    func save(signedInNow: Bool = false) {
        tasteRevision += 1
        let snap = Snapshot(profiles: profiles, activeProfileIDs: activeProfileIDs,
                            onboardingDone: onboardingDone, pendingRatings: pendingRatings,
                            account: account, signedIn: signedIn)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        if let account { db.upsert(account, state: data, signedInNow: signedInNow) }
        schedulePush(data)
    }

    /// Online speichern, kurz gesammelt: Viele Swipes hintereinander ergeben einen Upload.
    /// Der Upload gehört fest zu der Sitzung, in der gespeichert wurde, auch wenn danach das Konto wechselt.
    private func schedulePush(_ data: Data) {
        guard let session = cloudSession, signedIn else { return }
        pushTask?.cancel()
        let state = Self.onlineState(data)
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.push(state, with: session)
        }
    }

    /// Sofort hochladen (vor Abmelden oder Kontowechsel).
    private func pushNow() {
        guard let session = cloudSession, account != nil,
              let data = try? JSONEncoder().encode(Snapshot(profiles: profiles, activeProfileIDs: activeProfileIDs,
                                                            onboardingDone: onboardingDone, pendingRatings: pendingRatings,
                                                            account: account, signedIn: true)) else { return }
        pushTask?.cancel()
        let state = Self.onlineState(data)
        Task { await push(state, with: session) }
    }

    private func push(_ state: Data, with session: CloudAccounts.Session) async {
        guard let fresh = await CloudAccounts.valid(session) else { return }
        if cloudSession?.email == fresh.email { cloudSession = fresh }
        try? await CloudAccounts.saveState(state, session: fresh)
    }

    /// Online liegt kein Passwort-Hash, das Passwort prüft Supabase selbst.
    private static func onlineState(_ data: Data) -> Data {
        guard var snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return data }
        snap.account?.passwordHash = ""
        snap.account?.salt = ""
        snap.signedIn = nil
        return (try? JSONEncoder().encode(snap)) ?? data
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        apply(snap)
        signedIn = snap.signedIn ?? false
        // Online-Sitzung nach einem Neustart weiterverwenden, aber nur für genau dieses Konto.
        if signedIn, let s = CloudAccounts.storedSession, s.email == account?.email { cloudSession = s }
        // Älterer Stand von vor der Datenbank: Konto einmal übernehmen.
        if let account, db.record(account.email) == nil { db.upsert(account, state: data) }
    }

    private func apply(_ snap: Snapshot) {
        profiles = snap.profiles
        activeProfileIDs = snap.activeProfileIDs
        onboardingDone = snap.onboardingDone
        pendingRatings = snap.pendingRatings
        account = snap.account
        // Beim Start wählt man wie bei Netflix, wer schaut, außer es gibt nur ein Profil.
        hasChosenViewers = profiles.count <= 1
    }
}
