import SwiftUI
import Foundation
import UIKit
import CryptoKit
import MapKit

extension CommunityDetailView {
    // MARK: - Data & Link Helpers

    var socialLinks: [CommunitySocialLink] {
        let tags = area.tags ?? [:]
        let candidates: [(label: String, displayLabel: String?, icon: String?, keys: [String], base: String?)] = [
            ("X", "𝕏", nil, ["contact:x", "contact:twitter", "twitter"], "https://x.com/"),
            ("Facebook", nil, "f.cursive", ["contact:facebook", "facebook"], "https://facebook.com/"),
            ("Instagram", nil, "camera", ["contact:instagram", "instagram"], "https://instagram.com/"),
            ("Telegram", nil, "paperplane", ["contact:telegram", "telegram"], "https://t.me/"),
            ("GitHub", nil, "chevron.left.forwardslash.chevron.right", ["contact:github"], "https://github.com/"),
            ("LinkedIn", nil, "briefcase", ["contact:linkedin"], "https://linkedin.com/in/"),
            ("YouTube", nil, "play.rectangle", ["contact:youtube"], "https://youtube.com/"),
            ("Reddit", nil, "bubble.left.and.bubble.right", ["contact:reddit"], "https://reddit.com/"),
            ("Nostr", nil, "dot.radiowaves.left.and.right", ["contact:nostr"], nil)
        ]

        return candidates.compactMap { candidate in
            guard let rawValue = firstTagValue(for: candidate.keys, in: tags) else { return nil }
            let linkTarget: CommunityLinkTarget?
            if candidate.label == "Nostr" {
                linkTarget = nostrLinkTarget(for: rawValue)
            } else if let base = candidate.base {
                linkTarget = socialURL(for: rawValue, base: base).map { .web($0) }
            } else {
                linkTarget = websiteURL(from: rawValue).map { .web($0) }
            }
            return CommunitySocialLink(
                label: candidate.label,
                displayLabel: candidate.displayLabel ?? candidate.label,
                value: rawValue.cleanedForDisplay(),
                icon: candidate.icon,
                linkTarget: linkTarget
            )
        }
    }

    var contactInformationLinks: [CommunitySocialLink] {
        let tags = area.tags ?? [:]
        let candidates: [(label: String, icon: String, key: String)] = [
            ("Website", "globe", "contact:website"),
            ("Website", "globe", "website"),
            ("Email", "envelope", "contact:email"),
            ("Phone", "phone", "contact:phone"),
            ("Discord", "message", "contact:discord"),
            ("Eventbrite", "ticket", "contact:eventbrite"),
            ("Geyser", "bolt", "contact:geyser"),
            ("Matrix", "square.grid.3x3", "contact:matrix"),
            ("Meetup", "person.3", "contact:meetup"),
            ("RSS", "dot.radiowaves.right", "contact:rss"),
            ("Satlantis", "sparkles", "contact:satlantis"),
            ("Signal", "message.badge", "contact:signal"),
            ("SimpleX", "ellipsis.bubble", "contact:simplex"),
            ("WhatsApp", "phone.bubble", "contact:whatsapp")
        ]

        var seen = Set<String>()
        return candidates.compactMap { item -> CommunitySocialLink? in
            guard let rawValue = firstTagValue(for: [item.key], in: tags) else { return nil }
            let displayValue = rawValue.cleanedForDisplay()
            let dedupeKey = "\(item.label)|\(displayValue)"
            guard !seen.contains(dedupeKey) else { return nil }
            seen.insert(dedupeKey)
            return CommunitySocialLink(
                label: item.label,
                value: displayValue,
                icon: item.icon,
                linkTarget: resolvedContactURL(forKey: item.key, value: rawValue).map { .web($0) }
            )
        }
    }

    var primaryWebsiteURL: URL? {
        let tags = area.tags ?? [:]
        guard let raw = firstTagValue(for: ["contact:website", "website"], in: tags) else {
            return nil
        }
        return resolvedContactURL(forKey: "contact:website", value: raw)
    }

    private var btcMapCommunityURL: URL? {
        let rawSlug = area.tags?["url_alias"] ?? area.id
        let trimmed = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://btcmap.org/community/\(encoded)")
    }

    var shareableURL: URL? {
        primaryWebsiteURL ?? btcMapCommunityURL
    }

    var hasTipAction: Bool {
        payableLightningPayload != nil || tipFallbackURL != nil
    }

    private var tipValuesInPriority: [String] {
        let tags = area.tags ?? [:]
        let orderedKeys = ["tips:lightning_address", "tips:url", "ln_address"]
        var seen = Set<String>()
        return orderedKeys.compactMap { key in
            guard let raw = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            guard !seen.contains(raw) else { return nil }
            seen.insert(raw)
            return raw
        }
    }

    var payableLightningPayload: String? {
        tipValuesInPriority.compactMap(normalizedPayableLightningPayload).first
    }

    var tipFallbackURL: URL? {
        for value in tipValuesInPriority {
            if normalizedPayableLightningPayload(from: value) != nil { continue }
            if let fallback = nonPayableTipURL(from: value) {
                return fallback
            }
        }
        return nil
    }

    var knownWallets: [LightningWalletOption] {
        [
            .init(id: "cashapp", name: "Cash App", appURLs: urls(["cashapp://", "squarecash://"])),
            .init(id: "strike", name: "Strike", appURLs: urls(["strike://"])),
            .init(id: "bluewallet", name: "BlueWallet", appURLs: urls(["bluewallet://"])),
            .init(id: "phoenix", name: "Phoenix", appURLs: urls(["phoenix://"])),
            .init(id: "zeus", name: "Zeus", appURLs: urls(["zeusln://"])),
            .init(id: "muun", name: "Muun", appURLs: urls(["muun://"])),
            .init(id: "wos", name: "Wallet of Satoshi", appURLs: urls(["walletofsatoshi://"])),
            .init(id: "breez", name: "Breez", appURLs: urls(["breez://"])),
            .init(id: "aqua", name: "Aqua", appURLs: urls(["aqua://"]))
        ]
    }

    private var installedWallets: [LightningWalletOption] {
        knownWallets.filter { wallet in
            wallet.appURLs.contains { UIApplication.shared.canOpenURL($0) }
        }
    }

    var walletsForPicker: [LightningWalletOption] {
        installedWallets.isEmpty ? knownWallets : installedWallets
    }

    var verificationStatus: CommunityVerificationStatus? {
        guard let raw = area.tags?["verified:date"],
              let verifiedDate = parsedBTCMapDate(raw),
              let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: .now) else {
            return nil
        }
        let formattedDate = verifiedDate.formatted(date: .abbreviated, time: .omitted)
        if verifiedDate > oneYearAgo {
            return .init(
                icon: "checkmark.seal.fill",
                tint: .green,
                title: "Verified",
                statusText: String(format: NSLocalizedString("Last verified: %@", comment: "Verification status date label"), formattedDate),
                explanation: "Someone physically confirmed this community within the past year."
            )
        }
        return .init(
            icon: "exclamationmark.triangle.fill",
            tint: .orange,
            title: "Not Recently Verified",
            statusText: String(format: NSLocalizedString("Last verified: %@", comment: "Verification status date label"), formattedDate),
            explanation: "It has been more than a year since this community was verified."
        )
    }

    private func firstTagValue(for keys: [String], in tags: [String: String]) -> String? {
        keys.compactMap { key in
            tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first(where: { !$0.isEmpty })
    }

    func websiteURL(from value: String) -> URL? {
        let normalized = value.lowercased()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: value)
        }
        return URL(string: "https://\(value)")
    }

    private func socialURL(for value: String, base: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let handle = trimmed.replacingOccurrences(of: "@", with: "")
        return URL(string: base + handle)
    }

    private func resolvedContactURL(forKey key: String, value: String) -> URL? {
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

    var communityIconURL: URL? {
        guard let raw = area.tags?["icon:square"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return websiteURL(from: raw)
    }

    private func parsedBTCMapDate(_ raw: String) -> Date? {
        BTCMapDateParser.parse(raw)
    }

    private func normalizedPayableLightningPayload(from raw: String) -> String? {
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

    private func looksPayableLightningPayload(_ value: String) -> Bool {
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

    private func nonPayableTipURL(from raw: String) -> URL? {
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

    private func isLightningAddress(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard !local.contains(" "), !domain.contains(" ") else { return false }
        return domain.contains(".")
    }

    func openWallet(_ wallet: LightningWalletOption, payload: String) {
        let appURL = wallet.appURLs.first(where: { UIApplication.shared.canOpenURL($0) }) ?? wallet.appURLs.first
        guard let appURL else {
            lightningErrorMessage = NSLocalizedString("The selected wallet could not be opened.", comment: "Error shown when no wallet URL can be opened")
            return
        }
        UIPasteboard.general.string = payload
        UIApplication.shared.open(appURL, options: [:]) { success in
            if success {
                lastLightningWalletID = wallet.id
            } else {
                lightningErrorMessage = String(
                    format: NSLocalizedString(
                        "Could not open %@. The lightning value has been copied so you can paste it manually.",
                        comment: "Error shown when opening a specific wallet fails"
                    ),
                    wallet.name
                )
            }
        }
    }

    func openCommunityLink(_ item: CommunitySocialLink) {
        guard let linkTarget = item.linkTarget else { return }

        switch linkTarget {
        case .web(let url):
            openURL(url)
        case .appPreferred(let appURL):
            openURL(appURL) { accepted in
                guard !accepted else { return }
                linkOpenErrorItem = .nostr(copyValue: item.value)
            }
        }
    }

    private func nostrLinkTarget(for value: String) -> CommunityLinkTarget? {
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

    var sameSelectedCommunity: Bool {
        viewModel.selectedCommunityArea?.id == area.id
    }

    func updateMemberElements() {
        guard sameSelectedCommunity else {
            if !memberElements.isEmpty { memberElements = [] }
            return
        }
        let sorted = viewModel.communityMemberElements.sorted {
            let lhs = $0.displayName ?? $0.id
            let rhs = $1.displayName ?? $1.id
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        if sorted.map(\.id) != memberElements.map(\.id) {
            memberElements = sorted
        }
    }

    func cellViewModel(for element: Element) -> ElementCellViewModel {
        viewModel.cachedCellViewModel(for: element)
    }

    var isCollapsedLikeDetent: Bool {
        guard let detent = currentDetent else { return false }
        return detent == BottomSheetDetents.collapsed || detentIdentifier(detent).contains("fraction 0.11")
    }

    private var isLargeSheet: Bool {
        guard let detent = currentDetent else { return false }
        return detentIdentifier(detent).contains("large")
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }

    private func urls(_ values: [String]) -> [URL] {
        values.compactMap(URL.init(string:))
    }
}

struct CommunitySocialLink: Identifiable {
    let label: String
    let displayLabel: String
    let value: String
    let icon: String?
    let linkTarget: CommunityLinkTarget?

    init(
        label: String,
        displayLabel: String? = nil,
        value: String,
        icon: String?,
        linkTarget: CommunityLinkTarget?
    ) {
        self.label = label
        self.displayLabel = displayLabel ?? label
        self.value = value
        self.icon = icon
        self.linkTarget = linkTarget
    }

    var id: String { "\(label)|\(value)" }
    var isInteractive: Bool { linkTarget != nil }
}

enum CommunityLinkTarget {
    case web(URL)
    case appPreferred(appURL: URL)
}

struct CommunityLinkOpenError {
    let message: String
    let copyValue: String?

    static func nostr(copyValue: String) -> Self {
        Self(
            message: NSLocalizedString("It doesn't look like you have a Nostr app installed.", comment: "Error shown when trying to open a nostr profile without a compatible app"),
            copyValue: copyValue
        )
    }
}

struct CommunityVerificationStatus {
    let icon: String
    let tint: Color
    let title: String
    let statusText: String
    let explanation: String
}

struct LightningWalletOption: Identifiable {
    let id: String
    let name: String
    let appURLs: [URL]
}

struct ShareTextItem: Identifiable {
    let id = UUID()
    let items: [Any]

    init(text: String) {
        self.items = [text]
    }

    init(items: [Any]) {
        self.items = items
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

@MainActor
struct CommunityIconImage: View {
    let url: URL?
    let placeholderSystemName: String?
    let scaleToFill: Bool

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: scaleToFill ? .fill : .fit)
            } else if let placeholderSystemName {
                Image(systemName: placeholderSystemName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.accent)
            } else {
                Color.clear
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else {
                uiImage = nil
                return
            }
            uiImage = await CommunityIconCache.shared.image(for: url)
        }
    }
}

actor CommunityIconCache {
    static let shared = CommunityIconCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let directoryURL: URL

    private init() {
        directoryURL = URL.cachesDirectory.appending(path: "CommunityIconCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let fileURL = directoryURL.appending(path: fileName(for: url))
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: cacheKey)
            try? data.write(to: fileURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hash).img"
    }
}
