import Foundation

/// Import von Bewertungen aus Letterboxd (`ratings.csv` / `watched.csv` aus dem
/// Daten-Export) oder IMDb (Export „Your Ratings“). Erkannt wird das Format an den Spalten.
struct ImportResult {
    var source: String
    var totalRows: Int
    var matched: [(Film, Interaction)]
    /// Bewertete Filme, die nicht im Katalog sind, fließen trotzdem ins Geschmacksprofil,
    /// sobald Metadaten verfügbar sind (im Prototyp nur gezählt).
    var unmatchedCount: Int { totalRows - matched.count }
}

enum LibraryImport {

    static func parse(_ data: Data) -> ImportResult? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var rows = csvRows(text)
        guard !rows.isEmpty else { return nil }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func col(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }

        let isIMDb = header.contains("const") || header.contains("your rating")
        guard let titleCol = col("name", "title"), let yearCol = col("year") else { return nil }
        let ratingCol = col("rating", "your rating")
        let idCol = col("const")

        var matched: [(Film, Interaction)] = []
        for row in rows where row.count > max(titleCol, yearCol) {
            let title = row[titleCol]
            let year = Int(row[yearCol]) ?? 0
            let film = idCol.flatMap { i in row.count > i ? FilmIndex.all.first { $0.imdbID == row[i] } : nil }
                ?? FilmIndex.all.first { f in
                    (f.originalTitle.caseInsensitiveCompare(title) == .orderedSame || f.title.caseInsensitiveCompare(title) == .orderedSame)
                    && abs(f.year - year) <= 1
                }
            guard let film else { continue }
            var interaction = Interaction.liked
            if let ratingCol, row.count > ratingCol, let r = Double(row[ratingCol].replacingOccurrences(of: ",", with: ".")) {
                let stars = isIMDb ? r / 2 : r   // IMDb 1-10, Letterboxd 0,5-5
                interaction = stars >= 4.5 ? .loved : stars >= 3.5 ? .liked : stars >= 2.5 ? .ratedOkay : .disliked
            }
            matched.append((film, interaction))
        }
        return ImportResult(source: isIMDb ? "IMDb" : "Letterboxd", totalRows: rows.count, matched: matched)
    }

    /// Minimaler CSV-Parser mit Anführungszeichen-Unterstützung.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        var it = Array(text).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n } }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default: field.append(c)
                }
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
