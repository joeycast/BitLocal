import Foundation

/// Async/await wrappers around completion-based BTC Map repository APIs.
/// Keeps existing callers working while new code migrates to structured concurrency.
extension BTCMapRepositoryProtocol {
    func refreshElements() async -> [Element]? {
        await withCheckedContinuation { continuation in
            refreshElements { elements in
                continuation.resume(returning: elements)
            }
        }
    }

    func searchPlaces(query: V4SearchQuery) async throws -> [V4PlaceRecord] {
        try await withCheckedThrowingContinuation { continuation in
            searchPlaces(query: query) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchPlace(id: String) async throws -> V4PlaceRecord {
        try await withCheckedThrowingContinuation { continuation in
            fetchPlace(id: id) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchEvents(query: V4EventsQuery) async throws -> [V4EventRecord] {
        try await withCheckedThrowingContinuation { continuation in
            fetchEvents(query: query) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchPlaceComments(placeID: String) async throws -> [V4PlaceCommentRecord] {
        try await withCheckedThrowingContinuation { continuation in
            fetchPlaceComments(placeID: placeID) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchV2Areas(updatedSince: String, limit: Int) async throws -> [V2AreaRecord] {
        try await withCheckedThrowingContinuation { continuation in
            fetchV2Areas(updatedSince: updatedSince, limit: limit) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchV3Areas(updatedSince: String, limit: Int) async throws -> [V3AreaRecord] {
        try await withCheckedThrowingContinuation { continuation in
            fetchV3Areas(updatedSince: updatedSince, limit: limit) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchV3Area(id: Int) async throws -> V3AreaRecord {
        try await withCheckedThrowingContinuation { continuation in
            fetchV3Area(id: id) { result in
                continuation.resume(with: result)
            }
        }
    }

    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int) async throws -> [V3AreaElementRecord] {
        try await withCheckedThrowingContinuation { continuation in
            fetchV3AreaElements(areaID: areaID, updatedSince: updatedSince, limit: limit) { result in
                continuation.resume(with: result)
            }
        }
    }
}
