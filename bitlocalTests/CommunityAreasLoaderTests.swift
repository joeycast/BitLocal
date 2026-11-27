import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.sync))
struct CommunityAreasLoaderTests {
    /// Regression test: the loader is created as a local by its caller, so it
    /// must stay alive through async completions. A weak self capture in
    /// `step` deallocated it before the first page returned and onPage never
    /// fired. The stub completes asynchronously to reproduce that timing.
    @Test func loaderSurvivesCallingScopeWithAsyncRepository() async {
        let repository = AsyncStubRepository()
        repository.pages = [[makeArea(id: "a")]]

        let result: (ids: [String], isComplete: Bool, hasError: Bool) = await withCheckedContinuation { continuation in
            func kickOff() {
                let loader = CommunityAreasLoader(repository: repository)
                loader.loadAll { areas, isComplete, error in
                    continuation.resume(returning: (areas.map(\.id), isComplete, error != nil))
                }
            }
            kickOff() // loader local goes out of scope before the fetch completes
        }

        #expect(result.ids == ["a"])
        #expect(result.isComplete)
        #expect(result.hasError == false)
    }

    @Test func paginatesUntilShortPage() async {
        let repository = AsyncStubRepository()
        repository.pages = [
            [makeArea(id: "a", updatedAt: "2024-01-01T00:00:00Z"), makeArea(id: "b", updatedAt: "2024-01-02T00:00:00Z")],
            [makeArea(id: "c", updatedAt: "2024-01-03T00:00:00Z")]
        ]

        let result: (ids: Set<String>, pageCallCount: Int, hasError: Bool) = await withCheckedContinuation { continuation in
            var pageCallCount = 0
            var sawError = false
            let loader = CommunityAreasLoader(repository: repository, pageLimit: 2)
            loader.loadAll { areas, isComplete, error in
                pageCallCount += 1
                if error != nil {
                    sawError = true
                }
                if isComplete {
                    continuation.resume(returning: (Set(areas.map(\.id)), pageCallCount, sawError))
                }
            }
        }

        #expect(result.hasError == false)
        #expect(result.ids == ["a", "b", "c"])
        #expect(result.pageCallCount == 2)
    }

    private func makeArea(id: String, updatedAt: String = "2024-01-01T00:00:00Z") -> V2AreaRecord {
        V2AreaRecord(
            id: id,
            tags: nil,
            createdAt: "2023-01-01T00:00:00Z",
            updatedAt: updatedAt,
            deletedAt: nil,
            geoJSON: nil
        )
    }
}

/// Completes every call asynchronously off the calling thread, matching real
/// network timing so lifetime bugs in callers surface.
private final class AsyncStubRepository: BTCMapRepositoryProtocol, @unchecked Sendable {
    var pages: [[V2AreaRecord]] = []
    private var nextPageIndex = 0

    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V2AreaRecord], Error>) -> Void) {
        let page = nextPageIndex < pages.count ? pages[nextPageIndex] : []
        nextPageIndex += 1
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            completion(.success(page))
        }
    }

    func loadCachedElements() -> [Element]? { nil }
    func hasCachedData() -> Bool { false }
    func refreshElements(completion: @escaping @Sendable ([Element]?) -> Void) { completion(nil) }
    func lastSuccessfulSyncAtISO8601() -> String? { nil }
    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V3AreaRecord], Error>) -> Void) {
        completion(.success([]))
    }
    func fetchV3Area(id: Int, completion: @escaping @Sendable (Result<V3AreaRecord, Error>) -> Void) {
        completion(.failure(NSError(domain: "test", code: 1)))
    }
    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V3AreaElementRecord], Error>) -> Void) {
        completion(.success([]))
    }
    func searchPlaces(query: V4SearchQuery, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }
    func fetchPlace(id: String, completion: @escaping @Sendable (Result<V4PlaceRecord, Error>) -> Void) {
        completion(.failure(NSError(domain: "test", code: 1)))
    }
    func fetchEvents(query: V4EventsQuery, completion: @escaping @Sendable (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }
    func fetchPlaceComments(placeID: String, completion: @escaping @Sendable (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }
}
