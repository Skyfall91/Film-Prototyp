import Foundation
import FoundationModels

/// Strukturierte Interpretation einer freien Stimmungs-Anfrage.
/// Das Sprachmodell kennt den Katalog NICHT, es übersetzt nur die Anfrage
/// in Filter. Gesucht wird danach im eigenen Index (keine erfundenen Filme).
@Generable
struct MoodQuery {
    @Guide(description: "Passende Stimmungen, NUR aus dieser Liste: spannend, düster, lustig, gefühlvoll, episch, gemütlich, nachdenklich, gruselig, actionreich, romantisch, bildgewaltig, schräg, inspirierend, familienfreundlich, wendungsreich, musikalisch, leicht, intensiv, bunt, ruhig")
    var moods: [String]

    @Guide(description: "Passende Genres, NUR aus dieser Liste: Action, Abenteuer, Drama, Komödie, Science-Fiction, Fantasy, Horror, Thriller, Mystery, Krimi, Romanze, Animation, Biografie, Musical, Familie, Sport. Leer lassen, wenn unklar.")
    var genres: [String]

    @Guide(description: "Genres oder Stimmungen, die ausdrücklich NICHT gewünscht sind (gleiche Listen wie oben)")
    var exclude: [String]

    @Guide(description: "Maximale Laufzeit in Minuten, falls die Person eine Zeitangabe macht, sonst 0")
    var maxRuntimeMinutes: Int

    @Guide(description: "true, wenn Kinder mitschauen oder ein Familienfilm gewünscht ist")
    var familyFriendly: Bool

    @Guide(description: "Ein Filmtitel, falls die Person 'so wie X' oder 'ähnlich wie X' sagt, sonst leer")
    var similarTo: String

    @Guide(description: "Sehr kurze deutsche Zusammenfassung des Wunsches, max. 6 Wörter, z. B. 'Leichte Komödie für zwei'")
    var summary: String
}

struct MoodResult {
    var query: MoodQuery
    var films: [Recommendation]
    var usedAppleIntelligence: Bool
}

enum MoodSearch {

    static var isAppleIntelligenceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var availabilityNote: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Apple Intelligence · auf dem Gerät"
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence ist ausgeschaltet, Stichwortsuche aktiv"
        case .unavailable(.deviceNotEligible): "Gerät ohne Apple Intelligence, Stichwortsuche aktiv"
        case .unavailable(.modelNotReady): "Modell wird geladen, Stichwortsuche aktiv"
        default: "Stichwortsuche aktiv"
        }
    }

    static func search(_ text: String, profiles: [Profile]) async -> MoodResult {
        var query = keywordQuery(text)
        var usedAI = false
        if isAppleIntelligenceAvailable {
            do {
                let session = LanguageModelSession(instructions: """
                    Du bist die Suche eines Film-Streamingdienstes. Übersetze den Wunsch der Person \
                    in Filter. Nutze ausschließlich die vorgegebenen Begriffe. Erfinde keine Filme.
                    """)
                let response = try await session.respond(to: "Wunsch: \(text)", generating: MoodQuery.self)
                query = response.content
                usedAI = true
            } catch {
                // Fallback: Stichwortsuche (z. B. bei Guardrail-Treffern oder Modellfehlern)
            }
        }
        return MoodResult(query: query, films: rank(query, profiles: profiles), usedAppleIntelligence: usedAI)
    }

    // MARK: - Ranking im eigenen Index

    static func rank(_ q: MoodQuery, profiles: [Profile]) -> [Recommendation] {
        let moods = Set(q.moods.map { $0.lowercased() })
        let genres = Set(q.genres)
        let exclude = Set(q.exclude.map { $0.lowercased() })
        let reference = q.similarTo.isEmpty ? nil : FilmIndex.all.first {
            $0.title.localizedCaseInsensitiveContains(q.similarTo) || $0.originalTitle.localizedCaseInsensitiveContains(q.similarTo)
        }
        let fsk = min(profiles.map(\.maxFSK).min() ?? 18, q.familyFriendly ? 6 : 18)

        let scored: [(Film, Double)] = FilmIndex.all.compactMap { film in
            guard film.fsk <= fsk, profiles.allSatisfy({ $0.allows(film) }), film.id != reference?.id else { return nil }
            if q.maxRuntimeMinutes > 0, film.runtime > q.maxRuntimeMinutes { return nil }
            let tags = Set(film.moods) .union(film.genres.map { $0.lowercased() })
            if !tags.isDisjoint(with: exclude) { return nil }
            var s = Double(Set(film.moods).intersection(moods).count) * 2
            s += Double(Set(film.genres).intersection(genres).count) * 1.5
            if let reference {
                s += Double(Set(film.features.map(\.key)).intersection(reference.features.map(\.key)).count) * 0.9
            }
            if q.familyFriendly, film.moods.contains("familienfreundlich") { s += 2 }
            guard s > 0 || (moods.isEmpty && genres.isEmpty && reference == nil) else { return nil }
            // Persönlicher Geschmack als Feinsortierung
            s += profiles.isEmpty ? 0 : RecommendationEngine.groupScore(film, profiles: profiles) * 0.35
            if film.comingSoon { s -= 1.5 }
            return (film, s)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(12).map { film, _ in
            let personal = profiles.isEmpty ? 70 : RecommendationEngine.matchPercent(RecommendationEngine.groupScore(film, profiles: profiles))
            let hit = film.moods.filter(moods.contains).prefix(2).map(\.moodLabel)
            let reason = reference.map { "Ähnlich wie „\($0.title)“" }
                ?? (hit.isEmpty ? film.genres.prefix(2).joined(separator: " · ") : hit.joined(separator: " · "))
            return Recommendation(film: film, match: personal, reason: reason)
        }
    }

    // MARK: - Fallback ohne KI: Stichwörter → Filter

    static func keywordQuery(_ text: String) -> MoodQuery {
        let t = text.lowercased()
        let map: [(words: [String], moods: [String], genres: [String])] = [
            (["lustig", "witzig", "lachen", "komödie", "humor", "spaß"], ["lustig", "leicht"], ["Komödie"]),
            (["grusel", "horror", "angst", "schocker", "fürchten"], ["gruselig"], ["Horror"]),
            (["düster", "dunkel", "finster", "noir"], ["düster"], []),
            (["romant", "liebe", "date", "verliebt"], ["romantisch"], ["Romanze"]),
            (["spannend", "thriller", "nervenkitzel", "spannung"], ["spannend", "wendungsreich"], ["Thriller"]),
            (["action", "krawall", "explosion", "kampf", "verfolgung"], ["actionreich"], ["Action"]),
            (["kind", "familie", "familien"], ["familienfreundlich"], ["Animation", "Familie"]),
            (["gemütlich", "entspannt", "chill", "sonntag", "kuschel", "cozy"], ["gemütlich", "leicht"], []),
            (["nachdenk", "tiefgründig", "anspruchsvoll", "philosoph"], ["nachdenklich"], []),
            (["weltall", "weltraum", "space", "sci-fi", "zukunft", "planet", "alien"], [], ["Science-Fiction"]),
            (["musik", "musical", "singen", "tanzen"], ["musikalisch"], ["Musical"]),
            (["traurig", "weinen", "emotional", "berührend", "herz"], ["gefühlvoll"], ["Drama"]),
            (["episch", "bombast", "groß", "kino", "bildgewaltig"], ["episch", "bildgewaltig"], []),
            (["schräg", "verrückt", "abgedreht", "skurril", "weird"], ["schräg"], []),
            (["wendung", "twist", "überraschend", "rätsel"], ["wendungsreich"], ["Mystery"]),
            (["motiv", "inspir", "mut"], ["inspirierend"], []),
            (["ruhig", "langsam", "leise"], ["ruhig"], []),
            (["intensiv", "heftig", "krass"], ["intensiv"], [])
        ]
        var moods: [String] = [], genres: [String] = []
        for entry in map where entry.words.contains(where: t.contains) {
            moods += entry.moods; genres += entry.genres
        }
        var runtime = 0
        if let m = t.firstMatch(of: /(\d{2,3})\s*min/) { runtime = Int(m.1) ?? 0 }
        else if let m = t.firstMatch(of: /(\d)[,.]?(\d)?\s*(std|stunde)/) {
            runtime = (Int(m.1) ?? 0) * 60 + (m.2.flatMap { Int($0) }.map { $0 * 6 } ?? 0)
        } else if t.contains("kurz") || t.contains("nicht so lang") { runtime = 110 }
        var similar = ""
        if let m = t.firstMatch(of: /(?:wie|ähnlich wie|so wie)\s+(.+)$/) {
            let candidate = String(m.1).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if FilmIndex.all.contains(where: { $0.title.lowercased().contains(candidate) || $0.originalTitle.lowercased().contains(candidate) }) {
                similar = candidate
            }
        }
        return MoodQuery(moods: Array(Set(moods)), genres: Array(Set(genres)), exclude: [],
                         maxRuntimeMinutes: runtime, familyFriendly: t.contains("kind") || t.contains("famil"),
                         similarTo: similar, summary: "")
    }
}

// MARK: - Geschmacks-Satz mit Apple Intelligence (Fallback: Template)

enum TasteWriter {
    /// Die Fakten, aus denen der Satz entsteht. Ändern sie sich nicht, bleibt auch der Satz.
    private static func facts(_ summary: TasteSummary) -> String {
        """
        Lieblingsstimmungen: \(summary.topMoods.map(\.0).joined(separator: ", ")). \
        Lieblingsgenres: \(summary.topGenres.map(\.0).joined(separator: ", ")). \
        Lieblingsregie: \(summary.favoriteDirector ?? "keine"). \
        Eher nicht: \(summary.avoid.joined(separator: ", ")).
        """
    }

    private static func cacheKey(_ profile: Profile) -> String { "tasteSentence.\(profile.id)" }

    /// Bereits generierter Satz, solange die Geschmacksdaten unverändert sind, sofort, ohne Modellaufruf.
    static func cached(for profile: Profile) -> String? {
        guard let entry = UserDefaults.standard.dictionary(forKey: cacheKey(profile)) as? [String: String],
              entry["facts"] == facts(TasteSummary(profile: profile)) else { return nil }
        return entry["text"]?.withoutDashes
    }

    static func sentence(for profile: Profile) async -> (String, Bool) {
        let summary = TasteSummary(profile: profile)
        guard MoodSearch.isAppleIntelligenceAvailable, !summary.topMoods.isEmpty else { return (summary.sentence, false) }
        if let cached = cached(for: profile) { return (cached, true) }
        let facts = facts(summary)
        do {
            let session = LanguageModelSession(instructions: """
                Schreibe EINEN kurzen deutschen Satz (max. 25 Wörter), der den Filmgeschmack beschreibt. \
                Regeln: Beginne mit „Du“. Keine Begrüßung, keine Anrede, kein Name. \
                Verwende keine geschlechtsspezifischen Wörter (z. B. keine Personenbezeichnungen wie \
                Entdecker, Fan, Liebhaber, weder männlich noch weiblich). Keine Ich-Perspektive. \
                Keine Filmtitel und keine Personennamen. Keine Gedankenstriche.
                """)
            let text = try await session.respond(to: facts).content
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"„“")))
                .withoutDashes
            guard isNeutral(text) else { return (summary.sentence, false) }
            UserDefaults.standard.set(["facts": facts, "text": text], forKey: cacheKey(profile))
            return (text, true)
        } catch {
            return (summary.sentence, false)
        }
    }

    /// Sicherheitsnetz: Anreden oder gegenderte Personenbezeichnungen → neutraler Standardsatz.
    static func isNeutral(_ text: String) -> Bool {
        let t = text.lowercased()
        guard t.hasPrefix("du"), text.count < 220 else { return false }
        // „ich“ nur als ganzes Wort, sonst fliegen „dich“ und „mich“ mit raus.
        if t.firstMatch(of: /\bich\b/) != nil { return false }
        let banned = ["hallo", "hi ", "hey", "liebe ", "lieber ", "liebe:",
                      "entdeckerin", "entdecker", "liebhaberin", "liebhaber", "kennerin", "kenner",
                      "freundin", "freund ", "fan ", "cineast", "filmfan", "zuschauerin", "zuschauer"]
        if banned.contains(where: t.contains) { return false }
        // Typische weibliche Personenendungen („-erin“, „-istin“)
        return t.firstMatch(of: /\b\w+(erin|istin|innen)\b/) == nil
    }
}

// MARK: - Notlösung: Anreißer schreiben, wenn ein Film keine Beschreibung hat

/// Schreibt NUR aus gesicherten Metadaten (Genre, Stimmung, Regie, Laufzeit) einen
/// kurzen, spoilerfreien Anreißer. Keine Handlungsdetails, das kleine Modell kennt
/// viele Filme nicht und würde sonst raten. Ergebnis wird gecacht.
enum SynopsisWriter {
    static func teaser(for film: Film) async -> String? {
        let cacheKey = "teaser.\(film.id)"
        if let cached = UserDefaults.standard.string(forKey: cacheKey) { return cached.withoutDashes }
        guard MoodSearch.isAppleIntelligenceAvailable else { return nil }
        let facts = """
            Titel: \(film.title). Jahr: \(film.year). Genres: \(film.genres.joined(separator: ", ")). \
            Stimmung: \(film.moods.joined(separator: ", ")). Regie: \(film.director). Laufzeit: \(film.runtime) Minuten.
            """
        do {
            let session = LanguageModelSession(instructions: """
                Schreibe 1-2 kurze deutsche Sätze, die neugierig auf einen Film machen. \
                Nutze NUR die gegebenen Fakten, erfinde keine Handlung, keine Figuren und keine Wendungen. \
                Beschreibe Stimmung und Art des Films. Keine Anrede, keine gegenderten Wörter, keine Gedankenstriche.
                """)
            let text = try await session.respond(to: facts).content
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"„“")))
                .withoutDashes
            UserDefaults.standard.set(text, forKey: cacheKey)
            return text
        } catch {
            return nil
        }
    }
}
