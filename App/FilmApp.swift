import SwiftUI

@main
struct FilmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(store.accent)
                .task(priority: .utility) { await PosterCache.prefetchAll(FilmIndex.all.map(\.id)) }
                .task { try? await store.installCloudSync() }
                .onChange(of: store.signedIn) { _, ready in if ready { Task { try? await store.installCloudSync() } } }
                .onChange(of: scenePhase) { _, phase in if phase != .active { store.flush() } }
        }
    }
}

/// Die App ist im Hochformat gebaut, nur der Player darf ins Querformat drehen.
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
        .modifier(NearbyTVPairingPrompt())
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
    @State private var hero = HeroCoordinator()
    var body: some View {
        TabView(selection: Bindable(store).selectedTab) {
            Tab(FilmSection.forYou.title, systemImage: FilmSection.forYou.symbol, value: 0) { ForYouView() }
            Tab(FilmSection.watchlist.title, systemImage: FilmSection.watchlist.symbol, value: 1) { WatchlistView() }
            Tab(FilmSection.catalog.title, systemImage: FilmSection.catalog.symbol, value: 2) { CatalogView() }
            Tab(FilmSection.profile.title, systemImage: FilmSection.profile.symbol, value: 3) { ProfileTabView() }
            Tab(FilmSection.search.title, systemImage: FilmSection.search.symbol, value: 4, role: .search) { MoodSearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Solange Details offen sind, darf kein Tipper zu Knöpfen darunter durchrutschen
        // (z. B. Filtermenü genau unter dem Schließen-Knopf).
        .allowsHitTesting(hero.film == nil)
        .accessibilityHidden(hero.film != nil)
        .overlay { HeroOverlay() }
        .environment(hero)
        .sheet(item: Bindable(store).ratingToPresent) { RatingSheet(pending: $0) }
    }
}

/// Startparameter `-screen <name>` öffnet direkt einen Screen, für Folien-Screenshots.
