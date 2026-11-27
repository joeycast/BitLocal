import SwiftUI

extension ElementCategorySymbols {
    // MARK: - Internal Lookup

    private static func normalizedSearchTerm(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let allowedScalars = CharacterSet.alphanumerics.union(.whitespacesAndNewlines)
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

    private static func normalizedSearchTerms(_ values: [String]) -> Set<String> {
        Set(values.map(normalizedSearchTerm).filter { !$0.isEmpty })
    }

    private static func splitComponents(_ raw: String) -> [String] {
        raw.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Iterates over the components of a semicolon-separated tag value
    /// and returns the first matching Image found in `map`.
    private static func lookupSymbolName(in map: [String: String], forTagValue value: String) -> String? {
        let components = value.lowercased().components(separatedBy: ";")
        for component in components {
            let key = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if let symbolName = map[key] {
                return symbolName
            }
        }
        return nil
    }

    /// Resolve a BTC Map category/icon slug into an OSM tag key/value pair
    /// that this symbol mapper can use (for example `("amenity", "cafe")`).
    static func osmTagAssignment(forCategoryIcon icon: String?) -> (tagKey: String, tagValue: String)? {
        guard let icon else { return nil }
        let baseCandidates = icon
            .lowercased()
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var candidates = baseCandidates
        for candidate in baseCandidates {
            if let alias = categoryIconAliases[candidate], !alias.isEmpty {
                candidates.append(alias)
            }
        }

        for candidate in candidates {
            if cuisine[candidate] != nil { return ("cuisine", candidate) }
            if shop[candidate] != nil { return ("shop", candidate) }
            if sport[candidate] != nil { return ("sport", candidate) }
            if tourism[candidate] != nil { return ("tourism", candidate) }
            if healthcare[candidate] != nil { return ("healthcare", candidate) }
            if craft[candidate] != nil { return ("craft", candidate) }
            if amenity[candidate] != nil { return ("amenity", candidate) }
            if office[candidate] != nil { return ("office", candidate) }
            if place[candidate] != nil { return ("place", candidate) }
            if leisure[candidate] != nil { return ("leisure", candidate) }
            if building[candidate] != nil { return ("building", candidate) }
            if company[candidate] != nil { return ("company", candidate) }
        }

        return nil
    }

    static func symbolName(forCategoryIcon icon: String?) -> String? {
        guard let assignment = osmTagAssignment(forCategoryIcon: icon) else { return nil }
        switch assignment.tagKey {
        case "cuisine": return lookupSymbolName(in: cuisine, forTagValue: assignment.tagValue)
        case "shop": return lookupSymbolName(in: shop, forTagValue: assignment.tagValue)
        case "sport": return lookupSymbolName(in: sport, forTagValue: assignment.tagValue)
        case "tourism": return lookupSymbolName(in: tourism, forTagValue: assignment.tagValue)
        case "healthcare": return lookupSymbolName(in: healthcare, forTagValue: assignment.tagValue)
        case "craft": return lookupSymbolName(in: craft, forTagValue: assignment.tagValue)
        case "amenity": return lookupSymbolName(in: amenity, forTagValue: assignment.tagValue)
        case "office": return lookupSymbolName(in: office, forTagValue: assignment.tagValue)
        case "place": return lookupSymbolName(in: place, forTagValue: assignment.tagValue)
        case "leisure": return lookupSymbolName(in: leisure, forTagValue: assignment.tagValue)
        case "building": return lookupSymbolName(in: building, forTagValue: assignment.tagValue)
        case "company": return lookupSymbolName(in: company, forTagValue: assignment.tagValue)
        default: return nil
        }
    }

    /// Human-readable category for snapshot bootstrap places that lack real names.
    /// Prefer the primary merchant category chip label; fall back to a title-cased OSM tag.
    static func friendlyCategoryLabel(forIcon icon: String?) -> String? {
        if let group = merchantCategoryGroups(forCategoryIcon: icon).first {
            return group.localizedLabel
        }
        guard let assignment = osmTagAssignment(forCategoryIcon: icon) else { return nil }
        let raw = assignment.tagValue.replacing("_", with: " ")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.localizedCapitalized
    }

    static func merchantCategoryDescriptor(for group: MerchantCategoryGroup) -> MerchantCategoryDescriptor {
        if let descriptor = merchantCategoryDescriptors[group] {
            return descriptor
        }
        return MerchantCategoryDescriptor(
            group: group,
            chipSymbolName: "mappin.circle.fill",
            priority: Int.max,
            searchAliases: [],
            matchingTagValues: [],
            remoteTagFilters: [],
            iconOverrides: [],
            querySpecificTagFilters: [:]
        )
    }

    private struct PrecomputedGroupMatcher {
        let group: MerchantCategoryGroup
        let lowercasedIconOverrides: Set<String>
        let normalizedTerms: Set<String>
    }

    private static let precomputedGroupMatchers: [PrecomputedGroupMatcher] = {
        MerchantCategoryGroup.allCases
            .sorted {
                merchantCategoryDescriptor(for: $0).priority < merchantCategoryDescriptor(for: $1).priority
            }
            .map { group in
                let descriptor = merchantCategoryDescriptor(for: group)
                return PrecomputedGroupMatcher(
                    group: group,
                    lowercasedIconOverrides: Set(descriptor.iconOverrides.map { $0.lowercased() }),
                    normalizedTerms: normalizedSearchTerms(descriptor.matchingTagValues)
                )
            }
    }()

    private static let iconGroupCacheLock = NSLock()
    private static var iconGroupCache: [String: [MerchantCategoryGroup]] = [:]

    static func merchantCategoryGroups(for element: Element) -> [MerchantCategoryGroup] {
        var iconCandidates = Set<String>()
        if let icon = element.v4Metadata?.icon {
            iconCandidates.insert(icon.lowercased())
        }
        if let icon = element.tags?.iconPlatform {
            iconCandidates.insert(icon.lowercased())
        }

        // Fast path: when there are no OSM tags, reuse the icon-only cache.
        let tags = element.osmTagsDict
        if (tags == nil || tags?.isEmpty == true), iconCandidates.count == 1, let onlyIcon = iconCandidates.first {
            return merchantCategoryGroups(forCategoryIcon: onlyIcon)
        }

        var termCandidates = Set<String>()
        if let tags {
            for value in tags.values {
                for component in splitComponents(value) {
                    termCandidates.insert(normalizedSearchTerm(component))
                }
            }
        }

        for icon in iconCandidates {
            if let assignment = osmTagAssignment(forCategoryIcon: icon) {
                termCandidates.insert(normalizedSearchTerm(assignment.tagValue))
            }
            termCandidates.insert(normalizedSearchTerm(icon))
        }

        // precomputedGroupMatchers is already sorted by priority.
        var matched: [MerchantCategoryGroup] = []
        for matcher in precomputedGroupMatchers {
            if !matcher.lowercasedIconOverrides.isDisjoint(with: iconCandidates) ||
                !matcher.normalizedTerms.isDisjoint(with: termCandidates) {
                matched.append(matcher.group)
            }
        }
        return matched
    }

    static func merchantCategoryGroups(forCategoryIcon icon: String?) -> [MerchantCategoryGroup] {
        guard let icon, !icon.isEmpty else { return [] }
        let key = icon.lowercased()

        iconGroupCacheLock.lock()
        if let cached = iconGroupCache[key] {
            iconGroupCacheLock.unlock()
            return cached
        }
        iconGroupCacheLock.unlock()

        let iconSet: Set<String> = [key]
        var termCandidates = Set<String>()
        if let assignment = osmTagAssignment(forCategoryIcon: key) {
            termCandidates.insert(normalizedSearchTerm(assignment.tagValue))
        }
        termCandidates.insert(normalizedSearchTerm(key))

        var matched: [MerchantCategoryGroup] = []
        for matcher in precomputedGroupMatchers {
            if !matcher.lowercasedIconOverrides.isDisjoint(with: iconSet) ||
                !matcher.normalizedTerms.isDisjoint(with: termCandidates) {
                matched.append(matcher.group)
            }
        }

        iconGroupCacheLock.lock()
        if iconGroupCache.count < 1_024 {
            iconGroupCache[key] = matched
        }
        iconGroupCacheLock.unlock()
        return matched
    }

    static func merchantCategoryChips(for elements: [Element], limit: Int = 6) -> [MerchantCategoryChip] {
        var counts: [MerchantCategoryGroup: Int] = [:]
        for element in elements {
            for group in merchantCategoryGroups(for: element) {
                counts[group, default: 0] += 1
            }
        }

        return counts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return merchantCategoryDescriptor(for: lhs.key).priority < merchantCategoryDescriptor(for: rhs.key).priority
            }
            .prefix(limit)
            .map {
                MerchantCategoryChip(
                    group: $0.key,
                    count: $0.value,
                    symbolName: merchantCategoryDescriptor(for: $0.key).chipSymbolName
                )
            }
    }

    static func searchTerms(for group: MerchantCategoryGroup) -> [String] {
        let descriptor = merchantCategoryDescriptor(for: group)
        return [group.localizedLabel] + descriptor.searchAliases + descriptor.matchingTagValues
    }

    static func resolvedCategoryGroup(forNormalizedQuery normalizedQuery: String) -> MerchantCategoryGroup? {
        guard !normalizedQuery.isEmpty else { return nil }
        let matchingGroups = MerchantCategoryGroup.allCases.filter { group in
            normalizedSearchTerms(searchTerms(for: group)).contains(normalizedQuery)
        }
        return matchingGroups.count == 1 ? matchingGroups.first : nil
    }

    static func preferredRemoteTagFilters(
        for group: MerchantCategoryGroup,
        matchingNormalizedQuery normalizedQuery: String?,
        limit: Int
    ) -> [MerchantCategoryTagFilter] {
        guard limit > 0 else { return [] }
        let descriptor = merchantCategoryDescriptor(for: group)

        if let normalizedQuery,
           let overrides = descriptor.querySpecificTagFilters.first(where: {
               normalizedSearchTerm($0.key) == normalizedQuery
           })?.value {
            return Array(overrides.prefix(limit))
        }

        return Array(descriptor.remoteTagFilters.prefix(limit))
    }

    /// Returns a SwiftUI Image for an Element based on its OSM tags.
    static func image(for element: Element, renderingMode: Image.TemplateRenderingMode = .original) -> Image {
        let tags = element.osmTagsDict

        if let cuisineValue = tags?["cuisine"],
           let symbol = lookupSymbolName(in: cuisine, forTagValue: cuisineValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let shopValue = tags?["shop"],
           let symbol = lookupSymbolName(in: shop, forTagValue: shopValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let sportValue = tags?["sport"],
           let symbol = lookupSymbolName(in: sport, forTagValue: sportValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let tourismValue = tags?["tourism"],
           let symbol = lookupSymbolName(in: tourism, forTagValue: tourismValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let healthcareValue = tags?["healthcare"],
           let symbol = lookupSymbolName(in: healthcare, forTagValue: healthcareValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let craftValue = tags?["craft"],
           let symbol = lookupSymbolName(in: craft, forTagValue: craftValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let amenityValue = tags?["amenity"],
           let symbol = lookupSymbolName(in: amenity, forTagValue: amenityValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let officeValue = tags?["office"],
           let symbol = lookupSymbolName(in: office, forTagValue: officeValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let placeValue = tags?["place"],
           let symbol = lookupSymbolName(in: place, forTagValue: placeValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let leisureValue = tags?["leisure"],
           let symbol = lookupSymbolName(in: leisure, forTagValue: leisureValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let buildingValue = tags?["building"],
           let symbol = lookupSymbolName(in: building, forTagValue: buildingValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let companyValue = tags?["company"],
           let symbol = lookupSymbolName(in: company, forTagValue: companyValue) {
            return Image(systemName: symbol).renderingMode(renderingMode)
        }
        if let iconSymbol = symbolName(forCategoryIcon: element.v4Metadata?.icon ?? element.tags?.iconPlatform) {
            return Image(systemName: iconSymbol).renderingMode(renderingMode)
        }

        // Fallback if nothing matched:
        return Image(systemName: "bitcoinsign.circle.fill").renderingMode(renderingMode)
    }

    /// Returns the SF Symbol name for an Element by inspecting its OSM tags.
    static func symbolName(for element: Element) -> String {
        let tagsDict = element.osmTagsDict
        // 1) cuisine
        if let cuisineValue = tagsDict?["cuisine"],
           let name = lookupSymbolName(in: cuisine, forTagValue: cuisineValue) {
            return name
        }
        // 2) shop
        if let shopValue = tagsDict?["shop"],
           let name = lookupSymbolName(in: shop, forTagValue: shopValue) {
            return name
        }
        // 3) sport
        if let sportValue = tagsDict?["sport"],
           let name = lookupSymbolName(in: sport, forTagValue: sportValue) {
            return name
        }
        // 4) tourism
        if let tourismValue = tagsDict?["tourism"],
           let name = lookupSymbolName(in: tourism, forTagValue: tourismValue) {
            return name
        }
        // 5) healthcare
        if let healthcareValue = tagsDict?["healthcare"],
           let name = lookupSymbolName(in: healthcare, forTagValue: healthcareValue) {
            return name
        }
        // 6) craft
        if let craftValue = tagsDict?["craft"],
           let name = lookupSymbolName(in: craft, forTagValue: craftValue) {
            return name
        }
        // 7) amenity
        if let amenityValue = tagsDict?["amenity"],
           let name = lookupSymbolName(in: amenity, forTagValue: amenityValue) {
            return name
        }
        // 8) office
        if let officeValue = tagsDict?["office"],
           let name = lookupSymbolName(in: office, forTagValue: officeValue) {
            return name
        }
        // 9) place
        if let placeValue = tagsDict?["place"],
           let name = lookupSymbolName(in: place, forTagValue: placeValue) {
            return name
        }
        // 10) leisure
        if let leisureValue = tagsDict?["leisure"],
           let name = lookupSymbolName(in: leisure, forTagValue: leisureValue) {
            return name
        }
        // 11) building
        if let buildingValue = tagsDict?["building"],
           let name = lookupSymbolName(in: building, forTagValue: buildingValue) {
            return name
        }
        // 12) company
        if let companyValue = tagsDict?["company"],
           let name = lookupSymbolName(in: company, forTagValue: companyValue) {
            return name
        }
        if let iconSymbol = symbolName(forCategoryIcon: element.v4Metadata?.icon ?? element.tags?.iconPlatform) {
            return iconSymbol
        }
        // Fallback
        return "bitcoinsign.circle.fill"
    }
}
