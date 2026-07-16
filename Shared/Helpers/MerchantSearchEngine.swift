import Foundation
import CoreLocation

// MARK: - Search models (extracted from ContentViewModel)

struct MerchantSearchDocument: Equatable {
    let names: [String]
    let brandOperators: [String]
    let addresses: [String]
    let categoryTerms: [String]
    let rawTerms: [String]
    let allTerms: [String]
    let groups: [MerchantCategoryGroup]
}

struct MerchantSearchMatch: Equatable {
    let score: Int
    let matchedGroup: MerchantCategoryGroup?
    let exactLiteralHit: Bool

    var isStrong: Bool {
        score >= 700 || exactLiteralHit
    }
}

struct MerchantRemoteSearchPlan: Hashable {
    let query: V4SearchQuery
    let source: String
}

/// Pure matching / document-building helpers for merchant search.
/// Orchestration (debounce, network, published state) stays on ContentViewModel.
enum MerchantSearchEngine {
    // MARK: - Document building

    static func searchableTextFields(for element: Element) -> [String] {
        let tagValues = element.osmTagsDict?.values.flatMap {
            $0.components(separatedBy: ";")
        } ?? []
        let iconValues = [element.v4Metadata?.icon, element.tags?.iconPlatform]
            .compactMap { $0 }
            .flatMap { [$0, $0.replacingOccurrences(of: "_", with: " ")] }
        let groupValues = ElementCategorySymbols.merchantCategoryGroups(for: element).flatMap {
            ElementCategorySymbols.searchTerms(for: $0)
        }

        return (
            [
                element.osmJSON?.tags?.name,
                element.osmJSON?.tags?.brand,
                element.osmJSON?.tags?.operator,
                element.displayName,
                addressText(for: element),
                element.v4Metadata?.rawAddress
            ].compactMap { $0 } +
            tagValues +
            iconValues +
            groupValues
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static func documentSignature(for element: Element) -> String {
        searchableTextFields(for: element).joined(separator: "|")
    }

    static func document(for element: Element) -> MerchantSearchDocument {
        let groups = ElementCategorySymbols.merchantCategoryGroups(for: element)
        let groupTerms = groups.flatMap { ElementCategorySymbols.searchTerms(for: $0) }

        let names = normalizedSearchFields([
            element.osmJSON?.tags?.name,
            element.displayName
        ])
        let brandOperators = normalizedSearchFields([
            element.osmJSON?.tags?.brand,
            element.osmJSON?.tags?.operator
        ])
        let addresses = normalizedSearchFields([
            addressText(for: element),
            element.v4Metadata?.rawAddress
        ])
        let categoryTerms = normalizedSearchFields(groupTerms)
        let rawTerms = normalizedSearchFields(rawTerms(for: element))

        return MerchantSearchDocument(
            names: names,
            brandOperators: brandOperators,
            addresses: addresses,
            categoryTerms: categoryTerms,
            rawTerms: rawTerms,
            allTerms: Array(Set(names + brandOperators + addresses + categoryTerms + rawTerms)),
            groups: groups
        )
    }

    static func document(for record: V4PlaceRecord) -> MerchantSearchDocument {
        let element = V4PlaceToElementMapper.placeRecordToElement(record)
        let groups = ElementCategorySymbols.merchantCategoryGroups(for: element)
        let groupTerms = groups.flatMap { ElementCategorySymbols.searchTerms(for: $0) }
        let iconTerms = [record.icon].compactMap { $0 }.flatMap { [$0, $0.replacingOccurrences(of: "_", with: " ")] }

        let names = normalizedSearchFields([record.name, record.displayName])
        let brandOperators = normalizedSearchFields([record.osmBrand, record.osmOperator])
        let addresses = normalizedSearchFields([record.address])
        let categoryTerms = normalizedSearchFields(groupTerms)
        let rawTerms = normalizedSearchFields(
            (element.osmTagsDict?.values.flatMap { $0.components(separatedBy: ";") } ?? []) +
            iconTerms +
            [record.description].compactMap { $0 }
        )

        return MerchantSearchDocument(
            names: names,
            brandOperators: brandOperators,
            addresses: addresses,
            categoryTerms: categoryTerms,
            rawTerms: rawTerms,
            allTerms: Array(Set(names + brandOperators + addresses + categoryTerms + rawTerms)),
            groups: groups
        )
    }

    // MARK: - Matching

    static func match(
        document: MerchantSearchDocument,
        normalizedQuery: String,
        resolvedGroup: MerchantCategoryGroup?
    ) -> MerchantSearchMatch? {
        guard !normalizedQuery.isEmpty else { return nil }

        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        guard !queryTokens.isEmpty else { return nil }

        var score = 0
        var matchedGroup: MerchantCategoryGroup?
        let exactNameHit = containsPhrase(normalizedQuery, in: document.names)
        let exactBrandHit = containsPhrase(normalizedQuery, in: document.brandOperators)

        if exactNameHit {
            score = max(score, 1000)
        }
        if exactBrandHit {
            score = max(score, 920)
        }
        if tokenPrefixMatch(queryTokens, in: document.names) {
            score = max(score, 840)
        }

        if let resolvedGroup, document.groups.contains(resolvedGroup) {
            score = max(score, 780)
            matchedGroup = resolvedGroup
        }

        if containsPhrase(normalizedQuery, in: document.categoryTerms) {
            score = max(score, 720)
            matchedGroup = matchedGroup ?? document.groups.first
        } else if tokenPrefixMatch(queryTokens, in: document.categoryTerms) {
            score = max(score, 680)
            matchedGroup = matchedGroup ?? document.groups.first
        }

        if containsPhrase(normalizedQuery, in: document.rawTerms) {
            score = max(score, 620)
        }

        if tokenPrefixMatch(queryTokens, in: document.allTerms) {
            score = max(score, 560)
        } else if fuzzyTokenMatch(queryTokens, in: document.allTerms) {
            score = max(score, 520)
        }

        guard score > 0 else { return nil }
        return MerchantSearchMatch(
            score: score,
            matchedGroup: matchedGroup,
            exactLiteralHit: exactNameHit || exactBrandHit
        )
    }

    // MARK: - Filter helpers

    static func filterElements(
        _ source: [Element],
        normalizedQuery: String,
        documentProvider: (Element) -> MerchantSearchDocument
    ) -> (elements: [Element], scoresByID: [String: Int], strongHitCount: Int) {
        guard !normalizedQuery.isEmpty else {
            return ([], [:], 0)
        }
        let resolvedGroup = ElementCategorySymbols.resolvedCategoryGroup(forNormalizedQuery: normalizedQuery)
        let matched = source.compactMap { element -> (element: Element, match: MerchantSearchMatch)? in
            let document = documentProvider(element)
            guard let match = match(
                document: document,
                normalizedQuery: normalizedQuery,
                resolvedGroup: resolvedGroup
            ) else {
                return nil
            }
            return (element, match)
        }

        let scores = Dictionary(
            matched.map { ($0.element.id, $0.match.score) },
            uniquingKeysWith: { _, new in new }
        )
        let strong = matched.filter { $0.match.isStrong }.count
        return (matched.map(\.element), scores, strong)
    }

    static func filterRecords(
        _ records: [V4PlaceRecord],
        normalizedQuery: String
    ) -> [(record: V4PlaceRecord, score: Int)] {
        let resolvedGroup = ElementCategorySymbols.resolvedCategoryGroup(forNormalizedQuery: normalizedQuery)
        var deduplicatedByID: [String: V4PlaceRecord] = [:]
        for record in records where deduplicatedByID[record.idString] == nil {
            deduplicatedByID[record.idString] = record
        }

        return deduplicatedByID.values.compactMap { record -> (V4PlaceRecord, Int)? in
            let document = document(for: record)
            guard let match = match(
                document: document,
                normalizedQuery: normalizedQuery,
                resolvedGroup: resolvedGroup
            ) else {
                return nil
            }
            return (record, match.score)
        }
    }

    // MARK: - Private helpers

    private static func rawTerms(for element: Element) -> [String] {
        var terms = searchableTextFields(for: element)
        if let icon = element.v4Metadata?.icon ?? element.tags?.iconPlatform {
            terms.append(icon)
            terms.append(icon.replacingOccurrences(of: "_", with: " "))
        }
        return terms
    }

    private static func addressText(for element: Element) -> String? {
        let components = [
            element.address?.streetNumber,
            element.address?.streetName,
            element.address?.cityOrTownName,
            element.address?.regionOrStateName,
            element.address?.postalCode,
            element.address?.countryName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: " ")
    }

    private static func normalizedSearchFields(_ values: [String?]) -> [String] {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(SearchTextNormalizer.normalize)
            .filter { !$0.isEmpty }
    }

    private static func normalizedSearchFields(_ values: [String]) -> [String] {
        normalizedSearchFields(values.map(Optional.some))
    }

    private static func containsPhrase(_ normalizedQuery: String, in fields: [String]) -> Bool {
        fields.contains { $0.contains(normalizedQuery) }
    }

    private static func tokenPrefixMatch(_ queryTokens: [String], in fields: [String]) -> Bool {
        guard !queryTokens.isEmpty else { return false }
        return queryTokens.allSatisfy { queryToken in
            fields.contains { field in
                field.split(separator: " ").contains { String($0).hasPrefix(queryToken) }
            }
        }
    }

    private static func fuzzyTokenMatch(_ queryTokens: [String], in fields: [String]) -> Bool {
        guard !queryTokens.isEmpty else { return false }
        let candidateTokens = Set(fields.flatMap { $0.split(separator: " ").map(String.init) })
        return queryTokens.allSatisfy { queryToken in
            candidateTokens.contains(where: { candidate in
                candidate.hasPrefix(queryToken) || isOneEditAway(queryToken, candidate)
            })
        }
    }

    private static func isOneEditAway(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard abs(lhsChars.count - rhsChars.count) <= 1 else { return false }

        var i = 0
        var j = 0
        var edits = 0

        while i < lhsChars.count && j < rhsChars.count {
            if lhsChars[i] == rhsChars[j] {
                i += 1
                j += 1
                continue
            }

            edits += 1
            if edits > 1 { return false }

            if lhsChars.count > rhsChars.count {
                i += 1
            } else if rhsChars.count > lhsChars.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }

        if i < lhsChars.count || j < rhsChars.count {
            edits += 1
        }

        return edits <= 1
    }
}
