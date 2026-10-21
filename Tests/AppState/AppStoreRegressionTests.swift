import XCTest
@testable import FilmPrototyp

final class AppStoreRegressionTests: XCTestCase {
    @MainActor func testCloudSnapshotOmitsDeviceSelectionAndKeepsLocalViewer() throws {
        let store=AppStore(ephemeral:true)
        let a=Profile(name:"A",colorIndex:0,avatar:"scifi-0"), b=Profile(name:"B",colorIndex:1,avatar:"scifi-0")
        store.profiles=[a,b];store.activeProfileIDs=[b.id]
        let data=try JSONEncoder().encode(AppStore.Snapshot(profiles:[a,b],activeProfileIDs:[a.id],onboardingDone:true,pendingRatings:[],account:nil,signedIn:nil))
        var wire=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        wire.removeValue(forKey:"activeProfileIDs")
        try store.applyCloudSnapshot(JSONSerialization.data(withJSONObject:wire))
        XCTAssertEqual(store.activeProfileIDs,[b.id])
        XCTAssertEqual(store.profiles.map(\.name),["A","B"])
    }
    @MainActor func testRuntimeRangeAllowsOnlyFilmsBetweenBounds() {
        let range = RuntimeFilter(min: 90, max: 120)
        XCTAssertFalse(range.allows(89)); XCTAssertTrue(range.allows(90)); XCTAssertTrue(range.allows(120)); XCTAssertFalse(range.allows(121))
        XCTAssertEqual(range.label, "1,5 bis 2 Std.")
        XCTAssertEqual(RuntimeFilter(minutes: 105, atLeast: true).label, "ab 1:45 Std.")
        XCTAssertEqual(RuntimeFilter(minutes: 120).label, "bis 2 Std.")
    }
    @MainActor func testSearchForActorShowsOnlyTheirFilms() async {
        for text in ["Leonardo DiCaprio", "dicaprio", "lustige Filme mit DiCaprio"] {
            let result = await MoodSearch.search(text, profiles: [])
            XCTAssertFalse(result.films.isEmpty, text)
            XCTAssertTrue(result.films.allSatisfy { $0.film.cast.contains("Leonardo DiCaprio") }, text)
        }
        XCTAssertEqual(MoodSearch.people(in: "etwas Lustiges"), [])
        XCTAssertEqual(MoodSearch.people(in: "leonardo"), ["Leonardo DiCaprio"])
        XCTAssertEqual(MoodSearch.people(in: "Brad Pitt"), ["Brad Pitt"])
    }
    @MainActor func testOwnSyncConfirmationKeepsUndoAndDeck() throws {
        let store=AppStore(ephemeral:true)
        let profile=Profile(name:"A",colorIndex:0,avatar:"scifi-0")
        store.profiles=[profile];store.activeProfileIDs=[profile.id]
        let film=try XCTUnwrap(FilmIndex.film("dune"))
        store.apply(.notToday,to:film)
        XCTAssertTrue(store.canUndo)
        // Der Server bestätigt den eigenen Swipe und liefert den Stand leicht anders normalisiert zurück.
        var confirmed=store.profiles[0];confirmed.weights=[:]
        let snapshot=AppStore.Snapshot(profiles:[confirmed],activeProfileIDs:[],onboardingDone:true,pendingRatings:[],account:nil,signedIn:nil)
        let revision=store.tasteRevision
        try store.applyCloudSnapshot(JSONEncoder().encode(snapshot),fromOtherDevice:false)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.tasteRevision,revision)
    }
    @MainActor func testRemoteProfileChangeInvalidatesBroadUndo() throws {
        let store=AppStore(ephemeral:true)
        let profile=Profile(name:"A",colorIndex:0,avatar:"scifi-0")
        store.profiles=[profile];store.activeProfileIDs=[profile.id]
        let film=try XCTUnwrap(FilmIndex.film("dune"))
        store.apply(.watchlist,to:film)
        XCTAssertTrue(store.canUndo)
        var remote=store.profiles[0];remote.name="Vom anderen Gerät"
        let snapshot=AppStore.Snapshot(profiles:[remote],activeProfileIDs:[],onboardingDone:true,pendingRatings:[],account:nil,signedIn:nil)
        try store.applyCloudSnapshot(JSONEncoder().encode(snapshot))
        XCTAssertFalse(store.canUndo)
        store.undo()
        XCTAssertEqual(store.profiles.first?.name,"Vom anderen Gerät")
        XCTAssertTrue(store.profiles[0].watchlist.contains(film.id))
    }
    @MainActor func testPartialRatingKeepsOtherParticipantsPending() throws {
        let store=AppStore(ephemeral:true)
        let a=Profile(name:"A",colorIndex:0,avatar:"scifi-0"),b=Profile(name:"B",colorIndex:1,avatar:"scifi-0")
        store.profiles=[a,b];store.activeProfileIDs=[a.id]
        let pending=PendingRating(filmID:"dune",profileIDs:[a.id,b.id],date:.now)
        store.pendingRatings=[pending]
        store.rate(pending,ratings:[a.id:.ratedUp],reviews:[:])
        XCTAssertEqual(store.pendingRatings.first?.profileIDs,[b.id])
        XCTAssertEqual(store.profiles[0].interactions["dune"],.ratedUp)
        XCTAssertNil(store.profiles[1].interactions["dune"])
    }
    @MainActor func testPlaybackPositionsSeparateEpisodesAndIgnoreInvalidValues() {
        let store=AppStore(ephemeral:true)
        let a=Profile(name:"A",colorIndex:0,avatar:"scifi-0")
        store.profiles=[a];store.activeProfileIDs=[a.id]
        let episode=EpisodeRef(season:1,episode:2)
        store.savePlaybackPosition(filmID:"serie-dark",episode:episode,seconds:135)
        store.savePlaybackPosition(filmID:"serie-dark",episode:episode,seconds:Double.nan)
        XCTAssertEqual(store.playbackPosition(filmID:"serie-dark",episode:episode),135)
        XCTAssertNil(store.playbackPosition(filmID:"serie-dark",episode:EpisodeRef(season:1,episode:3)))
    }
    @MainActor func testOnlineSnapshotDoesNotExportPasswordOrSignedIn() throws {
        let store=AppStore(ephemeral:true)
        store.account=Account(email:"test@example.com",passwordHash:"secret-hash",salt:"secret-salt",created:.now,consented:.now)
        store.signedIn=true
        let data=try store.onlineSnapshotData()
        let text=String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains("secret-hash"));XCTAssertFalse(text.contains("secret-salt"))
        let wire=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertNil(wire["signedIn"])
    }
}

final class CatalogPosterRegressionTests: XCTestCase {
    @MainActor func testVisiblePosterSurvivesCachePressure() throws {
        let folder = URL.cachesDirectory.appending(path: "Posters", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.5))
        let ids = (0..<60).map { "cache-test-\(UUID().uuidString)-\($0)" }
        defer { for id in ids { try? FileManager.default.removeItem(at: folder.appending(path: "\(id).jpg")) } }
        for id in ids { try data.write(to: folder.appending(path: "\(id).jpg")) }
        let first = try XCTUnwrap(ids.first)
        PosterCache.warmUp([first])
        PosterCache.retainVisible(first)
        defer { PosterCache.releaseVisible(first) }
        let visibleImage = try XCTUnwrap(PosterCache.poster(first))
        for id in ids.dropFirst() { PosterCache.warmUp([id]) }
        XCTAssertTrue(PosterCache.poster(first) === visibleImage, "A visible catalog cover must not turn back into a placeholder")
    }
}

final class InteractionPerformanceRegressionTests: XCTestCase {
    @MainActor func testRidgeSolverPreservesSolutionAndFallback() {
        // A * [1,2,3] = [9,7,7]; SPD fixture, independent of the production solver.
        let solved = TasteModel.solveRidge([[4, 1, 1, 9], [1, 3, 0, 7], [1, 0, 2, 7]])
        for (actual, expected) in zip(solved, [1.0, 2.0, 3.0]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-10)
        }
        XCTAssertEqual(TasteModel.solveRidge([]), [])
        // Indefinite input uses pivoting fallback: x=2, y=1.
        XCTAssertEqual(TasteModel.solveRidge([[0, 1, 1], [1, 0, 2]]), [2, 1])
    }

    @MainActor func testRidgeSolverMatchesOriginalForCorrelatedHistory() {
        let n = 60
        let vectors = (0..<n).map { i in (0..<12).map { j in sin(Double(i * 3 + j)) } }
        let system = (0..<n).map { i in
            (0..<n).map { j in
                zip(vectors[i], vectors[j]).reduce(0.0) { $0 + $1.0 * $1.1 } + (i == j ? 3 : 0)
            } + [Double(i % 3) - 1]
        }
        for (actual, expected) in zip(TasteModel.solveRidge(system), TasteModel.solve(system)) {
            XCTAssertEqual(actual, expected, accuracy: 1e-9)
        }
    }
    // A synchronous cubic refit blocks swipe/undo and sync projection on the main actor.
    @MainActor func testLargeHistoryRefitStaysWithinMainActorBudget() {
        let samples = FilmIndex.all.prefix(200).enumerated().map {
            Profile.Sample(filmID: $0.element.id, target: $0.offset.isMultiple(of: 3) ? -1 : 1)
        }
        _ = TasteModel.fit(samples: Array(samples.prefix(6)), hints: [:])
        var durations: [Double] = []
        for _ in 0..<3 {
            let begin = CFAbsoluteTimeGetCurrent()
            let weights = TasteModel.fit(samples: samples, hints: [:])
            durations.append(CFAbsoluteTimeGetCurrent() - begin)
            XCTAssertFalse(weights.isEmpty)
            XCTAssertTrue(weights.values.allSatisfy(\.isFinite))
        }
        let median = durations.sorted()[1]
        print("PERF refit-200 median-ms=\(median * 1000)")
        XCTAssertLessThan(median, 0.08, "A 200-rating refit must not monopolize the UI actor")
    }

    @MainActor func testDetailCloseInterruptsOpeningInsteadOfWaitingForLanding() async throws {
        let hero = HeroCoordinator()
        let film = try XCTUnwrap(FilmIndex.film("dune"))
        hero.show(film, from: "test")
        hero.detailFrame = CGRect(x: 0, y: 0, width: 100, height: 150)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(hero.open)
        hero.close()
        await Task.yield()
        XCTAssertFalse(hero.open, "Closing must react immediately, even during the opening animation")
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertNil(hero.film, "A stale opening task must not reopen the detail")
    }

    @MainActor func testDetailClosedBeforeLayoutCannotReappear() async throws {
        let hero = HeroCoordinator()
        hero.show(try XCTUnwrap(FilmIndex.film("dune")), from: "test")
        hero.close()
        XCTAssertNil(hero.film)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(hero.film)
        XCTAssertFalse(hero.open)
    }

    @MainActor func testGhostReturnKeepsQueuedNextDetail() async throws {
        let hero = HeroCoordinator()
        let first = try XCTUnwrap(FilmIndex.film("dune"))
        let second = try XCTUnwrap(FilmIndex.all.first { $0.id != first.id })
        hero.sources[HeroCoordinator.key(first.id, "test")] = .init(
            frame: CGRect(x: 10, y: 20, width: 100, height: 150), radius: 12)
        hero.show(first, from: "test")
        hero.detailFrame = CGRect(x: 0, y: 0, width: 200, height: 300)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertNotNil(hero.ghost)
        hero.close()
        XCTAssertFalse(hero.open)
        hero.show(second, from: "next")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(hero.film?.id, second.id)
        hero.detailFrame = CGRect(x: 0, y: 0, width: 200, height: 300)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(hero.open)
        hero.close()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertNil(hero.film)
    }

    @MainActor func testSwipeUndoRestoresLargeHistoryExactly() throws {
        let store = AppStore(ephemeral: true)
        var profile = Profile(name: "Performance", colorIndex: 0)
        profile.samples = FilmIndex.all.prefix(200).map { .init(filmID: $0.id, target: 1) }
        profile.refit()
        store.profiles = [profile]; store.activeProfileIDs = [profile.id]
        let film = try XCTUnwrap(FilmIndex.film("dune"))
        let begin = CFAbsoluteTimeGetCurrent()
        store.apply(.watchlist, to: film)
        store.undo()
        let elapsed = CFAbsoluteTimeGetCurrent() - begin
        print("PERF swipe-plus-undo-200 ms=\(elapsed * 1000)")
        XCTAssertEqual(store.profiles, [profile])
        XCTAssertTrue(store.pendingRatings.isEmpty)
        XCTAssertFalse(store.canUndo)
        XCTAssertLessThan(elapsed, 0.12)
    }
}
