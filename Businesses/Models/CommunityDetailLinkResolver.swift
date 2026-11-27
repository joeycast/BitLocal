import Foundation

/// Pure link, contact, Nostr, and Lightning tipping URL/payload resolvers for `CommunityDetailView`.
enum CommunityDetailLinkResolver {
    static func websiteURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    static func socialURL(for value: String, base: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let handle = trimmed.replacingOccurrences(of: "@", with: "")
        return URL(string: base + handle)
    }

    static func resolvedContactURL(forKey key: String, value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        switch key {
        case "contact:website", "website":
            return websiteURL(from: trimmed)
        case "contact:email":
            return URL(string: "mailto:\(trimmed)")
        case "contact:phone":
            return URL(string: "tel:\(trimmed)")
        case "contact:github":
            return socialURL(for: trimmed, base: "https://github.com/")
        case "contact:linkedin":
            return socialURL(for: trimmed, base: "https://linkedin.com/in/")
        case "contact:discord":
            return socialURL(for: trimmed, base: "https://discord.gg/")
        case "contact:whatsapp":
            return socialURL(for: trimmed, base: "https://wa.me/")
        case "contact:matrix":
            return URL(string: "https://matrix.to/#/\(trimmed)")
        default:
            return websiteURL(from: trimmed)
        }
    }

    static func btcMapCommunityURL(areaID: String, urlAlias: String?) -> URL? {
        let rawSlug = urlAlias ?? areaID
        let trimmed = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://btcmap.org/community/\(encoded)")
    }

    static func normalizedPayableLightningPayload(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        // Support `lightning:<payload>` URIs only when payload looks wallet-payable.
        if lower.hasPrefix("lightning:") {
            let payload = String(trimmed.dropFirst("lightning:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return looksPayableLightningPayload(payload) ? payload : nil
        }

        return looksPayableLightningPayload(trimmed) ? trimmed : nil
    }

    static func looksPayableLightningPayload(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lnbcrt") {
            return true // BOLT11 invoices
        }
        if lower.hasPrefix("lno1") || lower.hasPrefix("lnr1") || lower.hasPrefix("lni1") {
            return true // BOLT12 offer / invoice request / invoice
        }
        if lower.hasPrefix("lnurl1") {
            return true // Bech32 LNURL
        }
        if isLightningAddress(value) {
            return true // LUD-16 identifier (name@domain)
        }
        return false
    }

    static func isLightningAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard !local.contains(" "), !domain.contains(" ") else { return false }
        return domain.contains(".")
    }

    static func nonPayableTipURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if isLightningAddress(trimmed) {
            let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let name = parts[0]
            let domain = parts[1]
            return URL(string: "https://\(domain)/\(name)")
        }
        return websiteURL(from: trimmed)
    }

    static func nostrLinkTarget(for value: String) -> CommunityLinkTarget? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: trimmed).map { .web($0) }
        }

        let identifier: String
        if lowered.hasPrefix("nostr:") {
            identifier = String(trimmed.dropFirst("nostr:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            identifier = trimmed
        }

        guard !identifier.isEmpty else { return nil }
        return URL(string: "nostr:\(identifier)").map { .appPreferred(appURL: $0) }
    }
}
