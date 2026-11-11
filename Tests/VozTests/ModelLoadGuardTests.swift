import Testing
@testable import Voz

@Suite struct ModelLoadGuardTests {
    @Test func keepsCompleteCache() async throws {
        let loadGuard = try makeModelLoadGuard()
        #expect(try await loadGuard.run { _ in 1 } == 1)
        #expect(cacheExists(loadGuard))
    }

    @Test(arguments: ["Encoder.mlmodelc/model.mil", "Encoder.mlmodelc/weights/weight.bin"])
    func removesOnlyTheBrokenBundle(_ path: String) async throws {
        let loadGuard = try makeModelLoadGuard()
        try removeCacheFile(path, from: loadGuard)
        _ = try await loadGuard.run { _ in }
        #expect(!cacheFileExists("Encoder.mlmodelc", in: loadGuard))
        #expect(cacheFileExists("vocab.json", in: loadGuard))
    }

    @Test func removesCacheMissingAFileFluidAudioWontFetch() async throws {
        let loadGuard = try makeModelLoadGuard()
        try removeCacheFile("vocab.json", from: loadGuard)
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == false)
    }

    @Test func quittingDuringTheDownloadIsNotACrash() async throws {
        let loadGuard = try makeModelLoadGuard()
        _ = try await loadGuard.begin()
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == true)
    }

    @Test func keepsBundleThatIsStillDownloading() async throws {
        let loadGuard = try makeModelLoadGuard()
        try removeCacheFile("Encoder.mlmodelc/model.mil", from: loadGuard)
        try writeCacheFile("Encoder.mlmodelc/weights/weight.bin.partial", in: loadGuard)
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == true)
    }

    @Test func marksTheLoadOnlyOnceCoreMLStarts() async throws {
        let loadGuard = try makeModelLoadGuard()
        _ = try await loadGuard.run { start in start.coreML() }
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == true)
    }

    @Test func removesCacheAfterLoadThatNeverFinished() async throws {
        let loadGuard = try makeModelLoadGuard()
        try await crashLoad(loadGuard)
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == false)
    }

    @Test func keepsCacheThatLoadsAfterAQuitDuringCompile() async throws {
        let loadGuard = try makeModelLoadGuard(loadsInChild: true)
        try await crashLoad(loadGuard)
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == true)
    }

    @Test func skipsLoadAfterThreeUnfinishedLoadsInOneBuild() async throws {
        let loadGuard = try makeModelLoadGuard(loadsInChild: true)
        for _ in 0..<ModelLoadGuard.unfinishedLoadsBeforeSkip { try await crashLoad(loadGuard) }
        #expect(try await loadGuard.run { _ in 1 } == nil)
        #expect(try await loadGuard.run { _ in 1 } == nil)
    }

    @Test func retriesSkippedModelInNewBuild() async throws {
        let skipped = try makeModelLoadGuard(build: "1.0", loadsInChild: true)
        for _ in 0..<ModelLoadGuard.unfinishedLoadsBeforeSkip { try await crashLoad(skipped) }
        let updated = ModelLoadGuard(cache: skipped.cache, files: skipped.files, build: "1.1", loadsInChild: { _ in true })
        #expect(try await updated.run { _ in 1 } == 1)
    }

    @Test func forgetsCrashOnceALoadFinishes() async throws {
        let loadGuard = try makeModelLoadGuard()
        try await crashLoad(loadGuard)
        #expect(try await loadGuard.run { _ in 1 } == 1)
        try await crashLoad(loadGuard)
        #expect(try await loadGuard.run { _ in 1 } == 1)
    }

    @Test func thrownLoadIsNotACrash() async throws {
        let loadGuard = try makeModelLoadGuard()
        await #expect(throws: ModelLoadGuardTestError.self) {
            try await loadGuard.run { _ in throw ModelLoadGuardTestError() }
        }
        #expect(try await loadGuard.run { _ in cacheExists(loadGuard) } == true)
    }

    @Test func loadsOfOneCacheTakeTurns() async throws {
        let loadGuard = try makeModelLoadGuard()
        let order = LoadOrder()
        let first = Task {
            try await loadGuard.run { _ in
                order.append("first start")
                try await Task.sleep(for: .milliseconds(300))
                order.append("first end")
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        _ = try await loadGuard.run { _ in order.append("second start") }
        _ = try await first.value
        #expect(order.all == ["first start", "first end", "second start"])
    }
}

struct ModelLoadGuardTestError: Error {}
