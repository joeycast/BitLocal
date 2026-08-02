import Foundation

struct DeepLinkUnavailableState: Identifiable {
    let id = UUID()
    let placeID: String
    let title: String
    let message: String
}

enum PlaceDeepLinkResolution: Equatable {
    case invalidIdentifier
    case deleted
    case success(Element)
    case failure(String)

    static func == (lhs: PlaceDeepLinkResolution, rhs: PlaceDeepLinkResolution) -> Bool {
        switch (lhs, rhs) {
        case (.invalidIdentifier, .invalidIdentifier), (.deleted, .deleted):
            return true
        case let (.success(l), .success(r)):
            return l.id == r.id
        case let (.failure(l), .failure(r)):
            return l == r
        default:
            return false
        }
    }
}

/// Resolves place share deep links against BTC Map without owning UI state.
/// ContentViewModel remains responsible for navigation and presentation.
final class PlaceDeepLinkResolver {
    private let repository: BTCMapSearchServiceProtocol

    init(repository: BTCMapSearchServiceProtocol) {
        self.repository = repository
    }

    func resolve(placeID: String, completion: @escaping (PlaceDeepLinkResolution) -> Void) {
        let trimmed = placeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlaceShareLinkBuilder.isValidPlaceID(trimmed) else {
            completion(.invalidIdentifier)
            return
        }

        repository.fetchPlace(id: trimmed) { result in
            switch result {
            case .success(let record):
                if let deletedAt = record.deletedAt, !deletedAt.isEmpty {
                    completion(.deleted)
                    return
                }
                completion(.success(V4PlaceToElementMapper.placeRecordToElement(record)))
            case .failure(let error):
                completion(.failure(error.localizedDescription))
            }
        }
    }

    /// The user-facing message is intentionally generic; the specific reason
    /// is only logged by the caller.
    static func unavailableState(placeID: String) -> DeepLinkUnavailableState {
        DeepLinkUnavailableState(
            placeID: placeID,
            title: NSLocalizedString("Place unavailable", comment: "Title for unavailable deep-linked place screen"),
            message: NSLocalizedString(
                "We could not open this BitLocal place. It may have been removed or is temporarily unavailable.",
                comment: "Message for unavailable deep-linked place screen"
            )
        )
    }

    static func invalidIdentifierReason() -> String {
        NSLocalizedString("Invalid place identifier.", comment: "Reason shown when a shared place ID is malformed")
    }

    static func deletedPlaceReason() -> String {
        NSLocalizedString("This place is no longer available.", comment: "Reason shown when a shared place has been removed")
    }
}
