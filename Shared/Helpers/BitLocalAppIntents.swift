import AppIntents
import Combine
import Foundation

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
            return "Saved"
        case .openNow:
            return "Open Now"
        case .lightning:
            return "Lightning"
        case .nfc:
            return "NFC"
        case .verified:
            return "Verified"
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

    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Place Filter")
    )

    static var caseDisplayRepresentations: [MerchantQuickFilter: DisplayRepresentation] = [
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

@MainActor
final class BitLocalAppIntentRouter: ObservableObject {
    static let shared = BitLocalAppIntentRouter()

    @Published var pendingAction: BitLocalIntentAction?

    init() {}

    func post(_ action: BitLocalIntentAction) {
        pendingAction = action
    }

    func consumePendingAction() -> BitLocalIntentAction? {
        let action = pendingAction
        pendingAction = nil
        return action
    }
}

struct FindNearbyBitcoinPlacesIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Nearby Bitcoin Places"
    static var description: IntentDescription? = IntentDescription("Open BitLocal to browse nearby places that accept Bitcoin.")
    static var openAppWhenRun: Bool = true

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
    static var title: LocalizedStringResource = "Find Lightning Places"
    static var description: IntentDescription? = IntentDescription("Open BitLocal filtered to nearby places accepting Bitcoin Lightning.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BitLocalAppIntentRouter.shared.post(.openMerchants(filter: .lightning, searchQuery: nil))
        }
        return .result()
    }
}

struct OpenBitcoinCommunitiesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Bitcoin Communities"
    static var description: IntentDescription? = IntentDescription("Open the Bitcoin communities view in BitLocal.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            BitLocalAppIntentRouter.shared.post(.openCommunities)
        }
        return .result()
    }
}

struct BitLocalAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

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
