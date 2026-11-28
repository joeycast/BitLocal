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
        let websiteLabel = String(localized: "Website", comment: "Contact label for a community website")
        let emailLabel = String(localized: "Email", comment: "Contact label for a community email")
        let phoneLabel = String(localized: "phone_label", comment: "Label for phone")
        let candidates: [(label: String, icon: String, key: String)] = [
            (websiteLabel, "globe", "contact:website"),
            (websiteLabel, "globe", "website"),
            (emailLabel, "envelope", "contact:email"),
            (phoneLabel, "phone", "contact:phone"),
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
        CommunityDetailLinkResolver.btcMapCommunityURL(
            areaID: area.id,
            urlAlias: area.tags?["url_alias"]
        )
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
                title: String(localized: "Verified", comment: "Community verification badge title"),
                statusText: String(localized: "Last verified: \(formattedDate)", comment: "Verification status date label"),
                explanation: String(
                    localized: "Someone physically confirmed this community within the past year.",
                    comment: "Explanation shown when a community was verified within the past year"
                )
            )
        }
        return .init(
            icon: "exclamationmark.triangle.fill",
            tint: .orange,
            title: String(localized: "Not Recently Verified", comment: "Community verification badge title when verification is older than a year"),
            statusText: String(localized: "Last verified: \(formattedDate)", comment: "Verification status date label"),
            explanation: String(
                localized: "It has been more than a year since this community was verified.",
                comment: "Explanation shown when a community has not been verified in over a year"
            )
        )
    }

    private func firstTagValue(for keys: [String], in tags: [String: String]) -> String? {
        keys.compactMap { key in
            tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first(where: { !$0.isEmpty })
    }

    func websiteURL(from value: String) -> URL? {
        CommunityDetailLinkResolver.websiteURL(from: value)
    }

    private func socialURL(for value: String, base: String) -> URL? {
        CommunityDetailLinkResolver.socialURL(for: value, base: base)
    }

    private func resolvedContactURL(forKey key: String, value: String) -> URL? {
        CommunityDetailLinkResolver.resolvedContactURL(forKey: key, value: value)
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
        CommunityDetailLinkResolver.normalizedPayableLightningPayload(from: raw)
    }

    private func nonPayableTipURL(from raw: String) -> URL? {
        CommunityDetailLinkResolver.nonPayableTipURL(from: raw)
    }

    func openWallet(_ wallet: LightningWalletOption, payload: String) {
        let appURL = wallet.appURLs.first(where: { UIApplication.shared.canOpenURL($0) }) ?? wallet.appURLs.first
        guard let appURL else {
            lightningErrorMessage = String(localized: "The selected wallet could not be opened.", comment: "Error shown when no wallet URL can be opened")
            return
        }
        UIPasteboard.general.string = payload
        UIApplication.shared.open(appURL, options: [:]) { success in
            if success {
                lastLightningWalletID = wallet.id
            } else {
                lightningErrorMessage = String(
                    localized: "Could not open \(wallet.name). The lightning value has been copied so you can paste it manually.",
                    comment: "Error shown when opening a specific wallet fails"
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
        CommunityDetailLinkResolver.nostrLinkTarget(for: value)
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

enum CommunityLinkTarget: Equatable, Sendable {
    case web(URL)
    case appPreferred(appURL: URL)
}

struct CommunityLinkOpenError {
    let message: String
    let copyValue: String?

    static func nostr(copyValue: String) -> Self {
        Self(
            message: String(localized: "It doesn't look like you have a Nostr app installed.", comment: "Error shown when trying to open a nostr profile without a compatible app"),
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
