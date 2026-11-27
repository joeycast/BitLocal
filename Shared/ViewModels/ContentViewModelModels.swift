import SwiftUI
import Foundation

enum MapDisplayMode: String {
    case merchants
    case communities
}

enum MerchantSearchScope: String, CaseIterable, Identifiable {
    case onMap = "Nearby"
    case worldwide = "Worldwide"

    var id: String { rawValue }
}

enum SearchTextNormalizer {
    private static let allowedScalars = CharacterSet.alphanumerics.union(.whitespacesAndNewlines)

    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        var cleaned = String.UnicodeScalarView()
        cleaned.reserveCapacity(folded.unicodeScalars.count)

        for scalar in folded.unicodeScalars {
            if allowedScalars.contains(scalar) {
                cleaned.append(scalar)
            } else {
                cleaned.append(" ")
            }
        }

        return String(cleaned)
            .replacing(#/\s+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func matches(normalizedQuery: String, normalizedCandidate: String) -> Bool {
        guard !normalizedQuery.isEmpty, !normalizedCandidate.isEmpty else { return false }
        if normalizedCandidate.contains(normalizedQuery) { return true }

        let queryTokens = normalizedTokens(from: normalizedQuery)
        let candidateTokens = normalizedTokens(from: normalizedCandidate)
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return false }

        return queryTokens.allSatisfy { queryToken in
            candidateTokens.contains(where: { candidateToken in
                candidateToken.hasPrefix(queryToken)
            })
        }
    }

    private static func normalizedTokens(from normalizedText: String) -> [String] {
        normalizedText
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

enum BitLocalNavigationRoute: Hashable {
    case place(Element)
    case placeComments(Element)
    case allEvents

    var element: Element? {
        switch self {
        case .place(let element), .placeComments(let element):
            return element
        case .allEvents:
            return nil
        }
    }

    var id: String {
        switch self {
        case .place(let element), .placeComments(let element):
            return element.id
        case .allEvents:
            return "all-events"
        }
    }
}

// DeepLinkUnavailableState lives in PlaceDeepLinkResolver.swift.
// MerchantSearchDocument/Match/Plan live in MerchantSearchEngine.swift.

struct VisibleCommunityListCacheKey: Equatable {
    let areasHash: Int
    let mapMode: MapDisplayMode
    let selectedCommunityID: String?
    let viewportMinXBucket: Int
    let viewportMinYBucket: Int
    let viewportMaxXBucket: Int
    let viewportMaxYBucket: Int
}
