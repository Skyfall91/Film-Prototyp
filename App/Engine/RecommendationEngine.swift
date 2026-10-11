import Foundation

/// Ein Vorschlag inkl. Begründung, „Warum dieser Film?“ ist Teil des Konzepts.
struct Recommendation: Identifiable, Hashable {
    var film: Film
    /// 0-100, wie gut der Film zur aktuellen Runde passt.
    var match: Int
    var reason: String
    var id: String { film.id }
}

/// Inhaltsbasierte Empfehlung: Filme werden über ihre Merkmale (Genre, Stimmung,
/// Regie, Besetzung) mit dem gelernten Geschmacksprofil verglichen.
/// Bei mehreren Profilen zählt vor allem, dass *niemand* leer ausgeht.
enum RecommendationEngine {

    /// Hybrid, getestet an 2.470 echten Personen (MovieLens):
    /// Filmbonus + „Leute wie du“ + etwas Qualität + Inhalt (Genre, Stimmung, Regie) + Chat-Hinweise.
    static func score(_ film: Film, for profile: Profile) -> Double {
        var collaborative = film.mlBias ?? 0
        if let q = film.mlFactors, q.count == profile.taste.count {
            collaborative += zip(q, profile.taste).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let content = film.features.reduce(0) { $0 + profile.weights[$1.key, default: 0] * $1.weight }
        let hints = film.features.reduce(0) { $0 + profile.hints[$1.key, default: 0] * $1.weight }
        // Serien werden auf IMDb im Schnitt gut eine Note besser bewertet als Filme (8,6 vs. 7,4), // ohne Ausgleich stünden sie fast immer oben.
        let quality = ((film.imdbRating ?? 7) - 7 - (film.isSeries ? 1.1 : 0)) * 0.08
        return collaborative + quality + 0.06 * content + 0.12 * hints
    }

    static func matchPercent(_ score: Double) -> Int {
        let p = 0.52 + 0.47 * tanh(score / 0.6)
        return Int((p * 100).rounded()).clamped(to: 20...99)
    }

    /// Kombinierter Wert für eine Runde mit mehreren Profilen („least misery“):
    /// Der schwächste Einzelwert zählt stärker als der Durchschnitt.
    static func groupScore(_ film: Film, profiles: [Profile]) -> Double {
        let scores = profiles.map { score(film, for: $0) }
        guard let minS = scores.min() else { return 0 }
        let mean = scores.reduce(0, +) / Double(scores.count)
        return profiles.count == 1 ? mean : 0.6 * minS + 0.4 * mean
    }

    static func candidates(profiles: [Profile], runtime: RuntimeFilter?, kind: KindFilter = .all, skipped: Set<String>) -> [Film] {
        return FilmIndex.all.filter { film in
            guard !film.comingSoon, profiles.allSatisfy({ $0.allows(film) }), !skipped.contains(film.id), kind.allows(film) else { return false }
            if let runtime, !runtime.allows(film.runtime) { return false }
            return !profiles.contains { $0.interactions[film.id]?.excludesFromDeck == true }
        }
    }

    static func recommendations(profiles: [Profile], runtime: RuntimeFilter?, kind: KindFilter = .all, skipped: Set<String>, limit: Int = 3) -> [Recommendation] {
        candidates(profiles: profiles, runtime: runtime, kind: kind, skipped: skipped)
            .map { ($0, groupScore($0, profiles: profiles)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { Recommendation(film: $0.0, match: matchPercent($0.1), reason: reason(for: $0.0, profiles: profiles)) }
    }

    // MARK: - Begründung

    static func reason(for film: Film, profiles: [Profile]) -> String {
        if profiles.count > 1 {
            let shared = film.features
                .map(\.key)
                .filter { key in profiles.allSatisfy { $0.affinity[key, default: 0] > 0.5 } }
                .sorted { a, b in
                    profiles.map { $0.affinity[a, default: 0] }.min()! > profiles.map { $0.affinity[b, default: 0] }.min()!
                }
                .prefix(2)
                .map(label)
            let names = profiles.map(\.name).formatted(.list(type: .and))
            if !shared.isEmpty {
                return "\(names) mögen \(shared.joined(separator: " & "))"
            }
            return "Passt für \(names), keiner geht leer aus"
        }
        guard let profile = profiles.first else { return "" }
        if let similar = mostSimilarFavorite(to: film, profile: profile) {
            return "Weil du „\(similar.title)“ mochtest"
        }
        if let top = film.features.map(\.key).max(by: { profile.affinity[$0, default: 0] < profile.affinity[$1, default: 0] }),
           profile.affinity[top, default: 0] > 0.3 {
            return "Weil du \(label(top)) magst"
        }
        return "Ein Volltreffer bei Kritikern, probier's aus"
    }

    static func mostSimilarFavorite(to film: Film, profile: Profile) -> Film? {
        // Zuerst „Leute wie du“: Welcher Lieblingsfilm wird von denselben Menschen gemocht?
        if let q = film.mlFactors {
            let best = profile.interactions
                .filter { $0.value.isPositive && $0.key != film.id }
                .compactMap { FilmIndex.film($0.key) }
                .compactMap { f in f.mlFactors.map { (f, cosine(q, $0)) } }
                .max { $0.1 < $1.1 }
            if let best, best.1 > 0.35 { return best.0 }
        }
        let target = Set(film.features.map(\.key))
        return profile.interactions
            .filter { $0.value.isPositive && $0.key != film.id }
            .compactMap { FilmIndex.film($0.key) }
            .map { ($0, Set($0.features.map(\.key)).intersection(target).count) }
            .filter { $0.1 >= 2 }
            .max { $0.1 < $1.1 }?.0
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let na = sqrt(a.reduce(0) { $0 + $1 * $1 }), nb = sqrt(b.reduce(0) { $0 + $1 * $1 })
        return na > 0 && nb > 0 ? dot / (na * nb) : 0
    }

    /// Lesbare Bezeichnung für ein Merkmal.
    static func label(_ key: String) -> String {
        let value = String(key.dropFirst(2))
        switch key.prefix(2) {
        case "m:": return value.moodLabel + "es"
        case "g:": return value
        case "d:": return "Filme von \(value)"
        default: return value
        }
    }
}

// MARK: - Zeitfilter

/// „Wie viel Zeit hast du?“, höchstens oder mindestens so lang.
/// Film, Serie oder beides, wählbar auf der Startseite.
enum KindFilter: String, CaseIterable, Identifiable {
    case all, films, series
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Beides"
        case .films: "Filme"
        case .series: "Serien"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.stack"
        case .films: "film"
        case .series: "tv"
        }
    }
    func allows(_ film: Film) -> Bool {
        switch self {
        case .all: true
        case .films: !film.isSeries
        case .series: film.isSeries
        }
    }
}

struct RuntimeFilter: Equatable {
    var minutes: Int
    var atLeast = false

    func allows(_ runtime: Int) -> Bool { atLeast ? runtime >= minutes : runtime <= minutes }

    /// „bis 2 Std.“ / „mind. 1 Std. 45 Min.“
    var label: String { (atLeast ? "mind. " : "bis ") + Self.duration(minutes) }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? (m > 0 ? "\(h) Std. \(m) Min." : "\(h) Std.") : "\(m) Min."
    }
}

// MARK: - Lernen: Ridge-Regression

/// Lernt aus den bewerteten Filmen, wie stark jedes Merkmal den Geschmack bestimmt.
/// Anders als einfaches Aufsummieren werden alle Merkmale *gemeinsam* geschätzt:
/// Liebt jemand drei düstere Nolan-Thriller, bekommt nicht jedes Merkmal den vollen
/// Kredit, sondern das, was die Bewertungen am besten erklärt. Offline-Test: +6-7 Punkte
/// Treffer gegenüber der Summen-Variante. Chat-Hinweise dienen als Vorwissen.
enum TasteModel {
    static let lambda = 3.0
    static let hintScale = 0.25
    static let maxSamples = 200

    /// „Leute wie du“: persönliche Faktoren aus den eigenen Swipes schätzen (Fold-in mit
    /// starker Regularisierung, λ = 100, im Test an echten Personen am besten).
    static func foldIn(samples: [Profile.Sample]) -> [Double] {
        let rows = samples.suffix(maxSamples).compactMap { s -> ([Double], Double, Double)? in
            guard let f = FilmIndex.film(s.filmID), let q = f.mlFactors else { return nil }
            return (q, stars(s.target), f.mlBias ?? 0)
        }
        guard let k = rows.first?.0.count, !rows.isEmpty else { return [] }
        let mean = rows.count > 2 ? rows.map(\.1).reduce(0, +) / Double(rows.count) : 0
        var a = [[Double]](repeating: [Double](repeating: 0, count: k + 1), count: k)
        for (q, y, bias) in rows {
            let target = y - 0.5 * mean - bias
            for i in 0..<k {
                for j in 0..<k { a[i][j] += q[i] * q[j] }
                a[i][k] += q[i] * target
            }
        }
        for i in 0..<k { a[i][i] += 100 }
        return solve(a)
    }

    /// Swipe-Signal → grobe Abweichung vom eigenen Schnitt (wie im Test: Liebe +1, Mag +0,3, Mag nicht −1).
    static func stars(_ signal: Double) -> Double {
        if signal >= 1.8 { return 1 }
        if signal > 0 { return 0.3 * min(signal, 1.5) }
        return max(signal, -1)
    }

    /// Gauß-Jordan für das erweiterte System [A | b].
    static func solve(_ m: [[Double]]) -> [Double] {
        var a = m; let n = a.count
        for c in 0..<n {
            let p = (c..<n).max { abs(a[$0][c]) < abs(a[$1][c]) }!
            a.swapAt(c, p)
            guard a[c][c] != 0 else { continue }
            for r in 0..<n where r != c {
                let f = a[r][c] / a[c][c]
                if f != 0 { for k in c...n { a[r][k] -= f * a[c][k] } }
            }
        }
        return (0..<n).map { a[$0][$0] != 0 ? a[$0][n] / a[$0][$0] : 0 }
    }

    static func fit(samples: [Profile.Sample], hints: [String: Double], external: [String: ExternalFilm] = [:]) -> [String: Double] {
        let prior = hints.mapValues { $0 * hintScale }
        let rows = samples.suffix(maxSamples).compactMap { s in
            (FilmIndex.film(s.filmID)?.features ?? external[s.filmID]?.features)
                .map { (Dictionary($0.map { ($0.key, $0.weight) }, uniquingKeysWith: +), s.target) }
        }
        guard !rows.isEmpty else { return prior }
        let n = rows.count
        // Zentriert: Wer fast alles mag, dem sagt ein „mag ich“ weniger.
        let mean = n > 2 ? rows.map(\.1).reduce(0, +) / Double(n) : 0
        func dot(_ a: [String: Double], _ b: [String: Double]) -> Double {
            a.reduce(0) { $0 + $1.value * (b[$1.key] ?? 0) }
        }
        // Kernel-Form: (XXᵀ + λI) α = y − X·w₀  →  w = w₀ + Xᵀα
        var a = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        for i in 0..<n {
            for j in i..<n {
                let k = dot(rows[i].0, rows[j].0)
                a[i][j] = k; a[j][i] = k
            }
            a[i][i] += lambda
            a[i][n] = rows[i].1 - 0.5 * mean - dot(rows[i].0, prior)
        }
        for c in 0..<n {
            let p = (c..<n).max { abs(a[$0][c]) < abs(a[$1][c]) }!
            a.swapAt(c, p)
            guard a[c][c] != 0 else { continue }
            for r in 0..<n where r != c {
                let f = a[r][c] / a[c][c]
                if f != 0 { for k in c...n { a[r][k] -= f * a[c][k] } }
            }
        }
        var w = prior
        for i in 0..<n where a[i][i] != 0 {
            let alpha = a[i][n] / a[i][i]
            for (key, x) in rows[i].0 { w[key, default: 0] += alpha * x }
        }
        return w
    }
}

// MARK: - Geschmacksprofil (für Onboarding-Abschluss & Profil-Tab)

struct TasteSummary {
    var topMoods: [(String, Double)]
    var topGenres: [(String, Double)]
    var favoriteDirector: String?
    var avoid: [String]

    init(profile: Profile) {
        func top(_ prefix: String, _ n: Int) -> [(String, Double)] {
            profile.affinity.filter { $0.key.hasPrefix(prefix) && $0.value > 0.2 }
                .sorted { $0.value > $1.value }
                .prefix(n)
                .map { (String($0.key.dropFirst(2)), $0.value) }
        }
        topMoods = top("m:", 4)
        topGenres = top("g:", 3)
        favoriteDirector = top("d:", 1).first.flatMap { $0.1 > 1.5 ? $0.0 : nil }
        avoid = profile.affinity.filter { ($0.key.hasPrefix("m:") || $0.key.hasPrefix("g:")) && $0.value < -0.8 }
            .sorted { $0.value < $1.value }.prefix(2).map { String($0.key.dropFirst(2)) }
    }

    /// Satz ohne KI, Fallback, wenn Apple Intelligence nicht verfügbar ist.
    var sentence: String {
        guard !topMoods.isEmpty || !topGenres.isEmpty else {
            return "Wir lernen dich gerade erst kennen. Jeder Swipe macht die Vorschläge besser."
        }
        var s = "Du stehst auf "
        let moods = topMoods.prefix(2).map(\.0)
        s += moods.isEmpty ? "gute Geschichten" : moods.map { $0 + "e" }.formatted(.list(type: .and)) + " Filme"
        if let g = topGenres.first?.0 { s += ", am liebsten \(g)" }
        s += "."
        if let d = favoriteDirector { s += " \(d) trifft deinen Nerv." }
        if let a = avoid.first { s += " \(a.moodLabel) eher nicht." }
        return s
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
