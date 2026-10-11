import Foundation
import SwiftData

/// Eine Zeile in der Konten-Datenbank: Anmeldedaten plus alles, was zum Konto gehört
/// (Abo, Profile, Bewertungen, Merklisten). So kommt man mit E-Mail und Passwort
/// jederzeit zu genau diesem Stand zurück, auch nach dem Abmelden oder mit mehreren Konten.
@Model
final class AccountRecord {
    @Attribute(.unique) var email: String
    /// Nur der Hash, nie das Passwort.
    var passwordHash: String
    var salt: String
    var created: Date
    var lastSignIn: Date
    /// Gespeicherter Zustand des Kontos (JSON).
    var state: Data

    init(email: String, passwordHash: String, salt: String, created: Date, lastSignIn: Date, state: Data) {
        self.email = email; self.passwordHash = passwordHash; self.salt = salt
        self.created = created; self.lastSignIn = lastSignIn; self.state = state
    }
}

/// Kleine echte Datenbank (SwiftData, darunter SQLite) auf dem Gerät.
/// Ein fertiger Dienst hätte dafür einen Server, damit das Konto auf jedem Gerät klappt.
final class AccountDatabase {
    private let context: ModelContext?

    init() {
        let url = URL.applicationSupportDirectory.appending(path: "Konten.store")
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let container = try? ModelContainer(for: AccountRecord.self, configurations: ModelConfiguration(url: url))
        context = container.map(ModelContext.init)
    }

    func record(_ email: String) -> AccountRecord? {
        var query = FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.email == email })
        query.fetchLimit = 1
        return try? context?.fetch(query).first
    }

    /// Alle Konten auf diesem Gerät, zuletzt genutzte zuerst.
    var emails: [String] {
        let query = FetchDescriptor<AccountRecord>(sortBy: [SortDescriptor(\.lastSignIn, order: .reverse)])
        return (try? context?.fetch(query).map(\.email)) ?? []
    }

    func upsert(_ account: Account, state: Data, signedInNow: Bool = false) {
        guard let context else { return }
        if let r = record(account.email) {
            r.passwordHash = account.passwordHash
            r.salt = account.salt
            r.state = state
            if signedInNow { r.lastSignIn = .now }
        } else {
            context.insert(AccountRecord(email: account.email, passwordHash: account.passwordHash, salt: account.salt,
                                         created: account.created, lastSignIn: .now, state: state))
        }
        try? context.save()
    }

    func delete(_ email: String) {
        guard let context, let r = record(email) else { return }
        context.delete(r)
        try? context.save()
    }
}
