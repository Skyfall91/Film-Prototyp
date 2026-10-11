import SwiftUI

@main
struct FilmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(store.accent)
                .task(priority: .utility) { await PosterCache.prefetchAll(FilmIndex.all.map(\.id)) }
        }
    }
}

/// Die App ist im Hochformat gebaut – nur der Player darf ins Querformat drehen.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var allowLandscape = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return Self.allowLandscape ? .allButUpsideDown : .portrait
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if DemoScreen.current == "calibrate" || DemoScreen.current == "reveal", let id = store.profiles.first?.id {
                OnboardingFlow(start: DemoScreen.current == "calibrate" ? .calibrate : .reveal, profileID: id) { _ in }
            } else if DemoScreen.current == "editor" {
                OnboardingFlow(mode: .addProfile) { _ in }
            } else if DemoScreen.current == "plan" {
                PlanPicker(mode: .onboarding) { _ in }
            } else if DemoScreen.current == "register" || DemoScreen.current == "login" {
                AuthFlow(start: DemoScreen.current == "register" ? .register : .login)
            } else if store.account == nil || !store.signedIn {
                AuthFlow()
                    .transition(.opacity)
            } else if !store.onboardingDone {
                OnboardingFlow { id in
                    withAnimation(.smooth) { store.finishOnboarding(profile: id) }
                }
                .transition(.opacity)
            } else if store.subscription == nil {
                // Älterer Stand ohne Abo (oder Konto gelöscht und neu angelegt): erst Tarif wählen.
                PlanPicker(mode: .onboarding) { _ in }
                    .transition(.opacity)
            } else if !store.hasChosenViewers {
                WhoIsWatchingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: store.onboardingDone)
        .animation(.smooth, value: store.hasChosenViewers)
        .animation(.smooth, value: store.signedIn)
        .animation(.smooth, value: store.subscription)
        .task {
            await store.syncSubscription()
            store.purchases.listen { sub in
                if let sub, store.subscription?.source != .demo { store.subscribe(sub) }
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        TabView(selection: Bindable(store).selectedTab) {
            Tab("Für dich", systemImage: "rectangle.stack.fill", value: 0) { ForYouView() }
            Tab("Liste", systemImage: "bookmark.fill", value: 1) { WatchlistView() }
            Tab("Katalog", systemImage: "square.grid.2x2.fill", value: 2) { CatalogView() }
            Tab("Profil", systemImage: "person.crop.circle.fill", value: 3) { ProfileTabView() }
            Tab("Suche", systemImage: "magnifyingglass", value: 4, role: .search) { MoodSearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: Bindable(store).ratingToPresent) { RatingSheet(pending: $0) }
    }
}

/// Startparameter `-screen <name>` öffnet direkt einen Screen – für Folien-Screenshots.
enum DemoScreen {
    static let current = UserDefaults.standard.string(forKey: "screen")
}
