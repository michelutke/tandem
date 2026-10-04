import Foundation
import Testing
import TandemCrypto
import TandemProtocol
import TandemTestSupport

@testable import FeatureFiles

@Suite struct ThumbnailCacheTests {
    private static let kib = 1024
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let pngTrailer = Data([
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ])

    private static func pngLike(size: Int, fill: UInt8 = 0x01) -> Data {
        let padding = size - pngSignature.count - pngTrailer.count
        return pngSignature + Data(repeating: fill, count: padding) + pngTrailer
    }

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: 32))
    }

    private struct Harness {
        let directory: URL
        let clock: ManualTestClock
        let cache: ThumbnailCache

        init(directory: URL? = nil, clock: ManualTestClock = ManualTestClock(), capBytes: Int = 1024 * 1024) throws {
            self.directory = directory ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("tandem-thumb-cache-test-\(UUID().uuidString)")
            self.clock = clock
            cache = try ThumbnailCache(
                directory: self.directory,
                capBytes: capBytes,
                now: FixedDateProvider(clock: clock).provider
            )
        }

        func tick() {
            clock.advance(by: .seconds(1))
        }

        func totalBytes() -> Int {
            let files = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            )
            var total = 0
            while let url = files?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
            }
            return total
        }

        func fileURLs() -> [URL] {
            let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            var urls: [URL] = []
            while let url = files?.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    urls.append(url)
                }
            }
            return urls
        }
    }

    @Test func thumbnailCache_repeatRequest_zeroServiceCalls() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let service = FakePhotoService(thumbnailBytes: Self.pngLike(size: 1 * Self.kib))
        let peer = try Self.fingerprint(0x01)
        let caching = CachingPhotoService(base: service, cache: harness.cache, peer: peer)

        _ = try await caching.fetchThumbnail(id: "photo-1", maxPx: 256)
        _ = try await caching.fetchThumbnail(id: "photo-1", maxPx: 256)

        #expect(await service.thumbRequests.count == 1)
    }

    @Test func thumbnailCache_differentMaxPx_isSeparateEntry() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)
        await harness.cache.store(Self.pngLike(size: 1 * Self.kib), peer: peer, id: "a", maxPx: 256)

        #expect(await harness.cache.data(peer: peer, id: "a", maxPx: 512) == nil)
        #expect(await harness.cache.data(peer: peer, id: "a", maxPx: 256) != nil)
    }

    @Test func thumbnailCache_fourEntriesOver1MiBCap_oldestEvictedTotalUnderCap() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)

        for id in ["a", "b", "c", "d"] {
            await harness.cache.store(Self.pngLike(size: 300 * Self.kib), peer: peer, id: id, maxPx: 256)
            #expect(harness.totalBytes() <= 1024 * Self.kib)
            harness.tick()
        }

        #expect(await harness.cache.data(peer: peer, id: "a", maxPx: 256) == nil)
        for id in ["b", "c", "d"] {
            #expect(await harness.cache.data(peer: peer, id: id, maxPx: 256) != nil)
        }
    }

    @Test func thumbnailCache_readBeforeInsert_leastRecentlyUsedEvictedInstead() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)
        for id in ["a", "b", "c"] {
            await harness.cache.store(Self.pngLike(size: 300 * Self.kib), peer: peer, id: id, maxPx: 256)
            harness.tick()
        }

        _ = await harness.cache.data(peer: peer, id: "a", maxPx: 256)
        harness.tick()
        await harness.cache.store(Self.pngLike(size: 300 * Self.kib), peer: peer, id: "d", maxPx: 256)

        #expect(await harness.cache.data(peer: peer, id: "b", maxPx: 256) == nil)
        #expect(await harness.cache.data(peer: peer, id: "a", maxPx: 256) != nil)
    }

    @Test func thumbnailCache_entryLargerThanCap_notStored() async throws {
        let harness = try Harness(capBytes: 100 * Self.kib)
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)

        await harness.cache.store(Self.pngLike(size: 200 * Self.kib), peer: peer, id: "a", maxPx: 256)

        #expect(await harness.cache.data(peer: peer, id: "a", maxPx: 256) == nil)
        #expect(harness.totalBytes() == 0)
    }

    @Test func thumbnailCache_reopenedFromSameDirectory_previousEntriesHit() async throws {
        let first = try Harness()
        defer { try? FileManager.default.removeItem(at: first.directory) }
        let peer = try Self.fingerprint(0x01)
        let bytes = Self.pngLike(size: 10 * Self.kib)
        await first.cache.store(bytes, peer: peer, id: "a", maxPx: 256)

        let reopened = try Harness(directory: first.directory)

        #expect(await reopened.cache.data(peer: peer, id: "a", maxPx: 256) == bytes)
    }

    @Test func thumbnailCache_reopenedFromSameDirectory_evictionOrderPreserved() async throws {
        let first = try Harness()
        defer { try? FileManager.default.removeItem(at: first.directory) }
        let peer = try Self.fingerprint(0x01)
        for id in ["a", "b", "c"] {
            await first.cache.store(Self.pngLike(size: 300 * Self.kib), peer: peer, id: id, maxPx: 256)
            first.tick()
        }

        let reopened = try Harness(directory: first.directory, clock: first.clock)
        await reopened.cache.store(Self.pngLike(size: 300 * Self.kib), peer: peer, id: "d", maxPx: 256)

        #expect(await reopened.cache.data(peer: peer, id: "a", maxPx: 256) == nil)
        #expect(await reopened.cache.data(peer: peer, id: "b", maxPx: 256) != nil)
    }

    @Test func thumbnailCache_corruptFile_missAndFileDeleted() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)
        let bytes = Self.pngLike(size: 10 * Self.kib)
        await harness.cache.store(bytes, peer: peer, id: "a", maxPx: 256)
        let file = try #require(harness.fileURLs().first)
        try bytes.prefix(5 * Self.kib).write(to: file)

        #expect(await harness.cache.data(peer: peer, id: "a", maxPx: 256) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func thumbnailCache_peerUnpaired_entriesForPeerDeleted() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let unpaired = try Self.fingerprint(0x01)
        let other = try Self.fingerprint(0x02)
        await harness.cache.store(Self.pngLike(size: 10 * Self.kib), peer: unpaired, id: "a", maxPx: 256)
        await harness.cache.store(Self.pngLike(size: 10 * Self.kib), peer: other, id: "a", maxPx: 256)

        try await harness.cache.purgeAll(peer: unpaired)

        #expect(await harness.cache.data(peer: unpaired, id: "a", maxPx: 256) == nil)
        #expect(await harness.cache.data(peer: other, id: "a", maxPx: 256) != nil)
    }

    @Test func thumbnailCache_storedFile_hasOwnerOnlyPermissions() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)
        await harness.cache.store(Self.pngLike(size: 10 * Self.kib), peer: peer, id: "a", maxPx: 256)

        let file = try #require(harness.fileURLs().first)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int

        #expect(mode == 0o600)
    }

    @Test func thumbnailCache_nonPNGBytes_notStored() async throws {
        let harness = try Harness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let peer = try Self.fingerprint(0x01)

        await harness.cache.store(Data("not a png".utf8), peer: peer, id: "a", maxPx: 256)

        #expect(harness.fileURLs().isEmpty)
    }
}
