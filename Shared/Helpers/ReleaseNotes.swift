import Foundation
import SwiftUI

struct ReleaseNotesHighlight: Identifiable, Equatable {
    let iconName: String
    let titleKey: String
    let detailKey: String

    var id: String { titleKey }

    var title: String {
        NSLocalizedString(titleKey, comment: "")
    }

    var detail: String {
        NSLocalizedString(detailKey, comment: "")
    }
}

struct ReleaseNotesEntry: Identifiable, Equatable {
    let version: String
    let highlights: [ReleaseNotesHighlight]

    var id: String { version }
}

enum ReleaseNotesCatalog {
    static let current: [ReleaseNotesEntry] = [
        ReleaseNotesEntry(
            version: "3.0",
            highlights: [
                ReleaseNotesHighlight(
                    iconName: "person.3.fill",
                    titleKey: "release_notes_3_0_communities_title",
                    detailKey: "release_notes_3_0_communities_detail"
                ),
                ReleaseNotesHighlight(
                    iconName: "magnifyingglass",
                    titleKey: "release_notes_3_0_search_title",
                    detailKey: "release_notes_3_0_search_detail"
                ),
                ReleaseNotesHighlight(
                    iconName: "bell.badge.fill",
                    titleKey: "release_notes_3_0_notifications_title",
                    detailKey: "release_notes_3_0_notifications_detail"
                ),
                ReleaseNotesHighlight(
                    iconName: "text.alignleft",
                    titleKey: "release_notes_3_0_details_title",
                    detailKey: "release_notes_3_0_details_detail"
                ),
                ReleaseNotesHighlight(
                    iconName: "square.and.arrow.up",
                    titleKey: "release_notes_3_0_sharing_title",
                    detailKey: "release_notes_3_0_sharing_detail"
                ),
                ReleaseNotesHighlight(
                    iconName: "translate",
                    titleKey: "release_notes_3_0_translation_title",
                    detailKey: "release_notes_3_0_translation_detail"
                ),
                ReleaseNotesHighlight(
                    iconName: "sparkles",
                    titleKey: "release_notes_3_0_quality_title",
                    detailKey: "release_notes_3_0_quality_detail"
                ),
            ]
        )
    ]

    static func entry(for version: String) -> ReleaseNotesEntry? {
        current.first { $0.version == version }
    }
}

@MainActor
final class ReleaseNotesController: ObservableObject {
    private enum StorageKey {
        static let lastSeenReleaseNotesVersion = "lastSeenReleaseNotesVersion"
    }

    @Published var activeReleaseNotes: ReleaseNotesEntry?

    private let userDefaults: UserDefaults
    private let currentVersion: String

    init(
        userDefaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    ) {
        self.userDefaults = userDefaults
        self.currentVersion = currentVersion
    }

    var isPresenting: Bool {
        activeReleaseNotes != nil
    }

    func evaluatePresentation(didCompleteOnboarding: Bool, isReadyForMainUI: Bool) {
        guard didCompleteOnboarding, isReadyForMainUI else { return }
        guard activeReleaseNotes == nil else { return }
        guard let entry = ReleaseNotesCatalog.entry(for: currentVersion) else { return }

        // Fresh installs should not see release notes for the version they just installed.
        // Mark the current version as seen the first time the app reaches a state where
        // release notes could be presented, then wait for the next update.
        guard let lastSeenVersion = userDefaults.string(forKey: StorageKey.lastSeenReleaseNotesVersion) else {
            userDefaults.set(entry.version, forKey: StorageKey.lastSeenReleaseNotesVersion)
            return
        }

        guard lastSeenVersion != entry.version else { return }

        activeReleaseNotes = entry
    }

    func dismiss() {
        guard let activeReleaseNotes else { return }

        userDefaults.set(activeReleaseNotes.version, forKey: StorageKey.lastSeenReleaseNotesVersion)
        self.activeReleaseNotes = nil
    }

    func presentCurrentReleaseNotes() {
        guard activeReleaseNotes == nil else { return }
        guard let entry = ReleaseNotesCatalog.entry(for: currentVersion) else { return }

        activeReleaseNotes = entry
    }
}
