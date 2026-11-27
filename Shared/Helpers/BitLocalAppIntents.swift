import AppIntents
import Foundation
import Observation

enum MerchantQuickFilter: String, CaseIterable, Identifiable, Hashable, AppEnum {
    case saved
    case openNow
    case lightning
    case nfc
    case verified

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .saved:
            return String(localized: "Saved", comment: "Quick filter chip for saved places")
        case .openNow:
            return String(localized: "Open Now", comment: "Quick filter chip for places currently open")
        case .lightning:
            return String(localized: "Lightning", comment: "Quick filter chip for Lightning-accepting places")
        case .nfc:
            return String(localized: "NFC", comment: "Quick filter chip for NFC/contactless Lightning places")
        case .verified:
            return String(localized: "Verified", comment: "Quick filter chip for recently verified places")
        }
    }

    var systemImage: String {
        switch self {
        case .saved:
            return "bookmark.fill"
        case .openNow:
            return "clock.fill"
        case .lightning:
            return "bolt.fill"
        case .nfc:
            return "wave.3.right"
        case .verified:
            return "checkmark.seal.fill"
        }
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Place Filter")
    )

    static let caseDisplayRepresentations: [MerchantQuickFilter: DisplayRepresentation] = [
        .saved: DisplayRepresentation(
            title: LocalizedStringResource("Saved"),
            image: .init(systemName: "bookmark.fill")
        ),
        .openNow: DisplayRepresentation(
            title: LocalizedStringResource("Open Now"),
            image: .init(systemName: "clock.fill")
        ),
        .lightning: DisplayRepresentation(
            title: LocalizedStringResource("Lightning"),
            image: .init(systemName: "bolt.fill")
        ),
        .nfc: DisplayRepresentation(
            title: LocalizedStringResource("NFC"),
            image: .init(systemName: "wave.3.right")
        ),
        .verified: DisplayRepresentation(
            title: LocalizedStringResource("Verified"),
            image: .init(systemName: "checkmark.seal.fill")
        )
    ]
}

enum BitLocalIntentAction: Equatable, Sendable {
    case openMerchants(filter: MerchantQuickFilter?, searchQuery: String?)
    case openCommunities
}

struct PendingIntentRequest: Equatable, Sendable {
    let id: UUID
    let action: BitLocalIntentAction

    init(id: UUID = UUID(), action: BitLocalIntentAction) {
        self.id = id
        self.action = action
    }
}

@MainActor
@Observable
final class BitLocalAppIntentRouter {
    static let shared = BitLocalAppIntentRouter()

    private(set) var pendingRequest: PendingIntentRequest?

    var pendingAction: BitLocalIntentAction? {
        pendingRequest?.action
    }

    init() {}

    func post(_ action: BitLocalIntentAction) {
        pendingRequest = PendingIntentRequest(action: action)
    }

    func consumePendingAction() -> BitLocalIntentAction? {
        let action = pendingRequest?.action
        pendingRequest = nil
        return action
    }

    /// Claims the queued App Intent action only for an active foreground scene,
    /// preventing background or secondary multi-window scenes from consuming it.
    func claimPendingAction(isSceneActive: Bool) -> BitLocalIntentAction? {
        guard isSceneActive, let request = pendingRequest else { return nil }
        pendingRequest = nil
        return request.action
    }
}

struct FindNearbyBitcoinPlacesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Nearby Bitcoin Places"
    static let description: IntentDescription? = IntentDescription("Open BitLocal to browse nearby places that accept Bitcoin.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Filter")
    var filter: MerchantQuickFilter?

    @Parameter(title: "Search")
    var query: String?

    init() {}

    init(filter: MerchantQuickFilter?, query: String?) {
        self.filter = filter
        self.query = query
    }

    func perform() async throws -> some IntentResult {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = (trimmedQuery?.isEmpty == false) ? trimmedQuery : nil
        let selectedFilter = filter

        await MainActor.run {
            BitLocalAppIntentRouter.shared.post(
                .openMerchants(filter: selectedFilter, searchQuery: normalizedQuery)
            )
        }
        return .result()
    }
}

struct FindLightningPlacesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Lightning Places"
    static let description: IntentDescription? = IntentDescription("Open BitLocal filtered to nearby places accepting Bitcoin Lightning.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BitLocalAppIntentRouter.shared.post(.openMerchants(filter: .lightning, searchQuery: nil))
        }
        return .result()
    }
}

struct OpenBitcoinCommunitiesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Bitcoin Communities"
    static let description: IntentDescription? = IntentDescription("Open the Bitcoin communities view in BitLocal.")
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BitLocalAppIntentRouter.shared.post(.openCommunities)
        }
        return .result()
    }
}

struct BitLocalAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindNearbyBitcoinPlacesIntent(),
            phrases: [
                "Find Bitcoin places in \(.applicationName)",
                "Find nearby Bitcoin places in \(.applicationName)",
                "Search Bitcoin merchants in \(.applicationName)"
            ],
            shortTitle: "Find Bitcoin Places",
            systemImageName: "bitcoinsign.circle.fill"
        )
        AppShortcut(
            intent: FindLightningPlacesIntent(),
            phrases: [
                "Find Lightning places in \(.applicationName)",
                "Show Bitcoin Lightning merchants in \(.applicationName)"
            ],
            shortTitle: "Lightning Places",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: OpenBitcoinCommunitiesIntent(),
            phrases: [
                "Open Bitcoin communities in \(.applicationName)",
                "Show Bitcoin communities in \(.applicationName)"
            ],
            shortTitle: "Bitcoin Communities",
            systemImageName: "person.3.fill"
        )
    }
}
