import SwiftUI

/// Akzentfarbe der App. Sie steht nur für Hauptaktion, Auswahl und Zustand, Farbe im Bild
/// kommt sonst aus den Postern. Varianten für die Farbsuche: Startparameter `-palette <name>`.
enum Theme {
    enum Palette: String, CaseIterable {
        /// Kinolicht: warmes Gold wie der Projektorstrahl im dunklen Saal.
        case honig
        /// Frisches Mint, verspielt, wie die neueren Apple-Apps.
        case minze
        /// Kinokarten-Rosa, laut und fröhlich.
        case rosa
        /// Jedes Profil bringt seine eigene Farbe mit.
        case profil
    }

    static let palette = Palette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .profil

    static func accent(for profile: Profile?) -> Color {
        switch palette {
        case .honig: Color(red: 1.0, green: 0.78, blue: 0.28)
        case .minze: Color(red: 0.36, green: 0.89, blue: 0.72)
        case .rosa: Color(red: 1.0, green: 0.55, blue: 0.75)
        case .profil: profile?.color ?? Color(red: 0.36, green: 0.55, blue: 1.0)
        }
    }
}
