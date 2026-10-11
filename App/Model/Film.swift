import SwiftUI

/// Ein Eintrag im Film-Index. Die Daten liegen gebündelt in `films.json`,
/// die Poster lädt `PosterCache` beim ersten Start aus dem Netz.
struct Film: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let originalTitle: String
    let year: Int
    let runtime: Int
    let genres: [String]
    let moods: [String]
    let director: String
    let cast: [String]
    let fsk: Int
    let synopsis: String
    let youtubeID: String
    let imdbID: String
    /// Adresse des Posters (IMDb-Bildserver), wird einmal geladen und dann auf dem Gerät gespeichert.
    var poster: String? = nil
    let imdbRating: Double?
    let rottenTomatoes: Int?
    let metascore: Int?
    /// Offizielle Trailer (deutsch zuerst, dann Originalfassung). Der erste ist „der Film“.
    let trailers: [Trailer]
    let comingSoon: Bool
    let releaseNote: String?
    /// Kleinere Filme, die vor allem Filmfans kennen.
    var niche: Bool = false
    /// Aus 32 Mio. echten Bewertungen (MovieLens): wie sehr Menschen den Film über ihrem
    /// eigenen Schnitt bewerten, und seine 24 „Geschmacksfaktoren“ („Leute wie du“).
    /// Bei ganz neuen Filmen aus Genre, Stimmung, Regie und IMDb geschätzt.
    let mlBias: Double?
    let mlFactors: [Double]?
    /// Anteil der Menschen, die den Film gesehen haben (für die Onboarding-Auswahl).
    let mlSeen: Double?
    /// Serien: „series“. Filme lassen das Feld weg. Bei Serien ist `runtime` die Länge einer Folge.
    var kind: String? = nil
    var endYear: Int? = nil
    var totalSeasons: Int? = nil
    var seasons: [Season]? = nil

    var isSeries: Bool { kind == "series" }

    /// Für kleine Kinder: ohne Altersbeschränkung und als Animations- oder Familientitel gedacht.
    /// (FSK 0 allein reicht nicht, auch „Notting Hill“ ist ab 0.)
    var forLittleKids: Bool { fsk == 0 && (genres.contains("Animation") || genres.contains("Familie")) }

    /// Merkmale, aus denen das Geschmacksprofil lernt, mit Gewichtung.
    /// Einmal pro Film berechnet: Die Empfehlung fragt sie bei jedem Swipe für alle Titel ab.
    var features: [(key: String, weight: Double)] { FilmIndex.features[id] ?? computeFeatures() }

    fileprivate func computeFeatures() -> [(key: String, weight: Double)] {
        genres.map { ("g:\($0)", 1.0) }
        + moods.map { ("m:\($0)", 1.2) }
        + (director.isEmpty ? [] : [("d:\(director)", 0.8)])
        + cast.prefix(2).map { ("c:\($0)", 0.4) }
    }

    /// Ein Satz, der neugierig macht: der erste Satz der handgeschriebenen, spoilerfreien Beschreibung.
    /// Genau ein Satz für die Vorschlagskarte: der erste Satz der Beschreibung.
    /// Abkürzungen („Dr.“, „P. T.“) beenden keinen Satz.
    var hook: String {
        let s = synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviations: Set<String> = ["dr", "mr", "mrs", "ms", "st", "nr", "jr", "sr", "prof", "ca", "vs", "bzw"]
        for end in s.matches(of: /(\S+)[.!?](?=\s|$)/) {
            let word = end.output.1.lowercased()
            if word.count > 1 && !abbreviations.contains(word) { return String(s[..<end.range.upperBound]) }
        }
        return s
    }

    var runtimeText: String {
        let h = runtime / 60, m = runtime % 60
        return h > 0 ? (m > 0 ? "\(h) Std. \(m) Min." : "\(h) Std.") : "\(m) Min."
    }

    var metaLine: String {
        isSeries ? "\(yearText) · \(seasonsText) · FSK \(fsk)" : "\(year) · \(runtimeText) · FSK \(fsk)"
    }

    /// „2008-2013“ bei abgeschlossenen Serien, sonst nur das Startjahr.
    var yearText: String {
        guard isSeries, let endYear, endYear != year else { return String(year) }
        return "\(year)-\(endYear)"
    }

    var seasonsText: String {
        let n = totalSeasons ?? seasons?.count ?? 1
        return n == 1 ? "1 Staffel" : "\(n) Staffeln"
    }

    /// Erste Folge, Startpunkt, wenn ein Profil die Serie noch nicht angefangen hat.
    var firstEpisode: EpisodeRef? {
        guard let s = seasons?.first, let e = s.episodes.first else { return nil }
        return EpisodeRef(season: s.number, episode: e.number)
    }

    func episode(_ ref: EpisodeRef) -> Episode? {
        seasons?.first { $0.number == ref.season }?.episodes.first { $0.number == ref.episode }
    }

    /// Folge nach `ref`, über Staffelgrenzen hinweg. `nil` am Serienende.
    func episode(after ref: EpisodeRef) -> EpisodeRef? {
        guard let seasons, let si = seasons.firstIndex(where: { $0.number == ref.season }) else { return nil }
        let eps = seasons[si].episodes
        if let ei = eps.firstIndex(where: { $0.number == ref.episode }), ei + 1 < eps.count {
            return EpisodeRef(season: ref.season, episode: eps[ei + 1].number)
        }
        guard si + 1 < seasons.count, let first = seasons[si + 1].episodes.first else { return nil }
        return EpisodeRef(season: seasons[si + 1].number, episode: first.number)
    }

    /// Dekodiertes Poster aus dem Cache, wird beim Swipen nicht jedes Frame neu geladen.
    var posterImage: UIImage? { PosterCache.poster(id) }
    /// Winzige Version für den unscharfen Hintergrund (Blur auf 40 px statt 800 px).
    var posterThumbnail: UIImage? { PosterCache.thumbnail(id) }
}

/// Ein Platz pro Poster. Views beobachten nur ihren eigenen Platz: Kommt ein Poster an,
/// zeichnet sich genau diese Kachel neu, nicht jede Kachel der App.
@Observable
final class PosterSlot {
    var image: UIImage?
    var thumb: UIImage?
}

/// Poster werden nicht mitgeliefert (Urheberrecht), sondern beim ersten Start aus dem Netz
/// geladen und auf dem Gerät gespeichert. Danach geht alles auch offline.
/// Lesen und Dekodieren läuft im Hintergrund; im Speicher bleiben nur die zuletzt
/// genutzten Poster (alle 417 dekodiert wären weit über 1 GB).
enum PosterCache {
    private static var slots: [String: PosterSlot] = [:]
    /// Zuletzt genutzte Poster, älteste zuerst.
    private static var recent: [String] = []
    private static let memoryLimit = 48
    private static var loading: Set<String> = []

    private static let folder: URL = {
        let url = URL.cachesDirectory.appending(path: "Posters", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func file(_ id: String) -> URL { folder.appending(path: "\(id).jpg") }

    private static func slot(_ id: String) -> PosterSlot {
        if let slot = slots[id] { return slot }
        let slot = PosterSlot()
        slots[id] = slot
        return slot
    }

    static func poster(_ id: String) -> UIImage? {
        let slot = slot(id)
        if let image = slot.image { touch(id); return image }
        load(id)
        return slot.image
    }

    /// Winzige Version für den unscharfen Hintergrund (Blur auf 40 px statt 800 px).
    static func thumbnail(_ id: String) -> UIImage? {
        let slot = slot(id)
        if slot.thumb == nil { load(id) }
        return slot.thumb
    }

    /// Lädt die nächsten Karten vor. Die erste sofort von der Festplatte, damit sie
    /// beim Erscheinen schon da ist; der Rest im Hintergrund.
    static func warmUp(_ ids: [String]) {
        for (i, id) in ids.enumerated() where slot(id).image == nil {
            if i == 0, let data = try? Data(contentsOf: file(id)), let image = UIImage(data: data) {
                store(id, image.preparingForDisplay() ?? image, thumb: makeThumb(image))
            } else {
                load(id)
            }
        }
    }

    /// Holt nach und nach alle fehlenden Poster auf die Festplatte (ohne sie zu dekodieren),
    /// damit Katalog und Suche später sofort Bilder haben. Was gerade zu sehen ist, geht vor.
    static func prefetchAll(_ ids: [String]) async {
        try? await Task.sleep(for: .seconds(2))
        let missing = ids.filter { !FileManager.default.fileExists(atPath: file($0).path) }
        await withTaskGroup(of: Void.self) { group in
            var next = missing.makeIterator()
            for _ in 0..<4 { if let id = next.next() { group.addTask { await prefetch(id) } } }
            for await _ in group { if let id = next.next() { group.addTask { await prefetch(id) } } }
        }
    }

    private static func prefetch(_ id: String) async {
        guard !loading.contains(id) else { return }
        _ = await download(id)
    }

    private static func load(_ id: String) {
        guard !loading.contains(id) else { return }
        loading.insert(id)
        let url = file(id)
        Task {
            defer { loading.remove(id) }
            var data = await read(url)
            if data == nil { data = await download(id) }
            guard let data, let decoded = await decode(data) else { return }
            store(id, decoded.image, thumb: decoded.thumb)
        }
    }

    private static func store(_ id: String, _ image: UIImage, thumb: UIImage) {
        let slot = slot(id)
        slot.image = image
        slot.thumb = thumb
        touch(id)
        // Ältestes Poster aus dem Speicher werfen; das kleine Vorschaubild bleibt.
        while recent.count > memoryLimit { slots[recent.removeFirst()]?.image = nil }
    }

    private static func touch(_ id: String) {
        if recent.last == id { return }
        recent.removeAll { $0 == id }
        recent.append(id)
    }

    private static func download(_ id: String) async -> Data? {
        guard let link = FilmIndex.film(id)?.poster, let url = URL(string: link),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        await write(data, to: file(id))
        return data
    }

    @concurrent nonisolated private static func read(_ url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }

    @concurrent nonisolated private static func write(_ data: Data, to url: URL) async {
        try? data.write(to: url, options: .atomic)
    }

    @concurrent nonisolated private static func decode(_ data: Data) async -> (image: UIImage, thumb: UIImage)? {
        guard let image = UIImage(data: data) else { return nil }
        return (image.preparingForDisplay() ?? image, makeThumb(image))
    }

    nonisolated private static func makeThumb(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 40, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

struct Season: Codable, Hashable, Sendable {
    let number: Int
    let episodes: [Episode]
}

struct Episode: Codable, Hashable, Sendable {
    let number: Int
    let title: String
}

/// Position in einer Serie („S2 · F4“).
struct EpisodeRef: Codable, Hashable, Sendable {
    var season: Int
    var episode: Int
    var short: String { "S\(season) · F\(episode)" }
}

struct Trailer: Codable, Hashable, Identifiable, Sendable {
    let id: String        // YouTube-ID
    let title: String     // „Trailer 2“, „Teaser“, „Original (OV)“
    let channel: String
    let german: Bool

    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
}

enum FilmIndex {
    static let all: [Film] = {
        guard let url = Bundle.main.url(forResource: "films", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let films = try? JSONDecoder().decode([Film].self, from: data) else { return [] }
        return films
    }()

    static let byID: [String: Film] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func film(_ id: String) -> Film? { byID[id] }

    static let features: [String: [(key: String, weight: Double)]] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.computeFeatures()) })

    static let allGenres: [String] = Array(Set(all.flatMap(\.genres))).sorted()
    static let allMoods: [String] = Array(Set(all.flatMap(\.moods))).sorted()

    /// Bekanntheit innerhalb der eigenen Zeit: Wie oft wurde der Film gesehen, verglichen mit
    /// anderen bekannten Filmen aus denselben Jahren? (MovieLens-Daten reichen bis 2023, neue Filme
    /// hätten sonst nie eine Chance gegen die Klassiker der 90er.) Wer neue Filme kennt, bekommt sie
    /// trotzdem schnell: Der Picker lernt den Zeitraum mit.
    static let familiarity: [String: Double] = {
        let films = all.filter { !$0.isSeries && !$0.comingSoon }
        var result: [String: Double] = [:]
        for f in films {
            // Ab 2023 enden die MovieLens-Daten, die Zahlen dort sind nicht verlässlich: neutral zählen.
            if f.year >= 2023 { result[f.id] = f.niche ? 0.2 : 1; continue }
            let peers = films.filter { !$0.niche && abs($0.year - f.year) <= 2 }.compactMap(\.mlSeen).sorted()
            let median = peers.isEmpty ? 0.01 : peers[peers.count / 2]
            result[f.id] = min((f.mlSeen ?? 0) / max(median, 0.0005), 4)
        }
        return result
    }()
}

/// Wählt beim Kennenlernen den nächsten Film so, dass man ihn möglichst schon gesehen hat:
/// zuerst die bekanntesten Filme, und dabei lernt sie, aus welcher Zeit jemand Filme kennt.
/// Wer z. B. alte Klassiker als „Nicht gesehen“ wischt, bekommt danach neuere Filme.
struct CalibrationPicker {
    /// Gesehen / nicht gesehen je Zeitraum, startet neutral (1:1).
    private var seen: [Int: Double] = [:]
    private var unseen: [Int: Double] = [:]
    private var total = 0, totalSeen = 0
    private let pool: [Film]

    init(profile: Profile?, excluding rated: Set<String>) {
        // Nur Filme: Das Lernen aus echten Bewertungen (MovieLens) ist für Filme geprüft.
        pool = FilmIndex.all.filter { !$0.isSeries && !$0.comingSoon && (profile?.allows($0) ?? true) && !rated.contains($0.id) }
    }

    private static func era(_ year: Int) -> Int {
        switch year {
        case ..<1990: 0
        case ..<2005: 1
        case ..<2015: 2
        case ..<2020: 3
        default: 4
        }
    }

    /// Chance, dass jemand einen Film aus diesem Zeitraum kennt.
    private func chance(_ film: Film) -> Double {
        let e = Self.era(film.year)
        return (seen[e, default: 0] + 1) / (seen[e, default: 0] + unseen[e, default: 0] + 2)
    }

    mutating func record(_ film: Film, seen wasSeen: Bool) {
        let e = Self.era(film.year)
        if wasSeen { seen[e, default: 0] += 1; totalSeen += 1 } else { unseen[e, default: 0] += 1 }
        total += 1
    }

    /// Die nächsten Filme, die am wahrscheinlichsten schon gesehen wurden (mit etwas Zufall,
    /// damit nicht jeder dieselbe Reihe bekommt). Geheimtipps erst, wenn jemand viel kennt.
    func next(_ count: Int, excluding shown: Set<String>) -> [Film] {
        let seenRate = total == 0 ? 0.5 : Double(totalSeen) / Double(total)
        let nicheWeight = total < 6 ? 0.05 : 0.1 + 0.5 * seenRate
        var rng = SystemRandomNumberGenerator()
        return pool.filter { !shown.contains($0.id) }
            .map { f -> (Film, Double) in
                let known = (FilmIndex.familiarity[f.id] ?? 0).squareRoot()
                return (f, known * chance(f) * (f.niche ? nicheWeight : 1) * Double.random(in: 0.75...1.25, using: &rng))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map(\.0)
    }
}

/// Darstellung der Stimmungs-Tags (Index nutzt Kleinschreibung).
extension String {
    var moodLabel: String { prefix(1).uppercased() + dropFirst() }

    /// Gedankenstriche aus KI-Texten entfernen: Die App verwendet keine.
    /// Zahlenbereiche bekommen einen Bindestrich, sonst wird ein Komma daraus.
    var withoutDashes: String {
        replacing(/(\d)\s?[\u{2013}\u{2014}]\s?(\d)/) { "\($0.1)-\($0.2)" }
            .replacing(/\s*[\u{2013}\u{2014}]\s*/, with: ", ")
    }
}
