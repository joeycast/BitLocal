import CloudKit
import Combine
import Foundation

@MainActor
final class SavedPlacesStore: ObservableObject {
    static let shared = SavedPlacesStore()

    @Published private(set) var savedIDs: Set<String>

    private static let userDefaultsKey = "bitlocal.savedPlaceIDs.v1"
    private static let cloudKitContainerIdentifier = "iCloud.app.bitlocal.bitlocal"
    private static let recordType = "SavedPlace"
    private static let placeIDField = "placeID"
    private static let recordNamePrefix = "saved-"

    private let userDefaults: UserDefaults
    private lazy var container = CKContainer(identifier: Self.cloudKitContainerIdentifier)
    private var isSyncing = false
    private var pendingRemovals: Set<String> = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let stored = userDefaults.stringArray(forKey: Self.userDefaultsKey) {
            self.savedIDs = Set(stored)
        } else {
            self.savedIDs = []
        }

        Task { [weak self] in
            await self?.syncFromCloudIfAvailable()
        }
    }

    func isSaved(_ placeID: String) -> Bool {
        savedIDs.contains(placeID)
    }

    func toggleSaved(_ placeID: String) {
        guard !placeID.isEmpty else { return }

        let shouldSave: Bool
        if savedIDs.contains(placeID) {
            savedIDs.remove(placeID)
            pendingRemovals.insert(placeID)
            shouldSave = false
        } else {
            savedIDs.insert(placeID)
            pendingRemovals.remove(placeID)
            shouldSave = true
        }

        persistToUserDefaults()

        Task { [weak self] in
            guard let self else { return }
            if shouldSave {
                await self.saveRecordToCloudIfAvailable(placeID: placeID)
            } else {
                await self.deleteRecordFromCloudIfAvailable(placeID: placeID)
            }
        }
    }

    func syncFromCloudIfAvailable() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard await isCloudKitAvailable() else { return }

        do {
            let database = container.privateCloudDatabase
            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            var remoteIDs = Set<String>()

            let initialPage = try await database.records(
                matching: query,
                desiredKeys: [Self.placeIDField]
            )
            for (_, result) in initialPage.matchResults {
                if case .success(let record) = result, let placeID = placeID(from: record) {
                    remoteIDs.insert(placeID)
                }
            }

            var cursor = initialPage.queryCursor
            while let activeCursor = cursor {
                let nextPage = try await database.records(
                    continuingMatchFrom: activeCursor,
                    desiredKeys: [Self.placeIDField]
                )
                for (_, result) in nextPage.matchResults {
                    if case .success(let record) = result, let placeID = placeID(from: record) {
                        remoteIDs.insert(placeID)
                    }
                }
                cursor = nextPage.queryCursor
            }

            remoteIDs.subtract(pendingRemovals)
            let merged = savedIDs.union(remoteIDs)
            if merged != savedIDs {
                savedIDs = merged
                persistToUserDefaults()
            }
        } catch {
            // CloudKit sync is best-effort; silently ignore errors for offline/unavailable states.
        }
    }

    private func persistToUserDefaults() {
        userDefaults.set(Array(savedIDs).sorted(), forKey: Self.userDefaultsKey)
    }

    private func isCloudKitAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    private func recordID(for placeID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(Self.recordNamePrefix)\(placeID)")
    }

    private func placeID(from record: CKRecord) -> String? {
        if let placeID = record[Self.placeIDField] as? String, !placeID.isEmpty {
            return placeID
        }
        let recordName = record.recordID.recordName
        if recordName.hasPrefix(Self.recordNamePrefix) {
            let suffix = String(recordName.dropFirst(Self.recordNamePrefix.count))
            return suffix.isEmpty ? nil : suffix
        }
        return nil
    }

    private func saveRecordToCloudIfAvailable(placeID: String) async {
        guard await isCloudKitAvailable() else { return }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID(for: placeID))
        record[Self.placeIDField] = placeID as CKRecordValue

        do {
            _ = try await container.privateCloudDatabase.save(record)
        } catch {
            // Silently ignore CloudKit write failures (e.g. offline or already-saved record).
        }
    }

    private func deleteRecordFromCloudIfAvailable(placeID: String) async {
        guard await isCloudKitAvailable() else { return }

        do {
            _ = try await container.privateCloudDatabase.deleteRecord(withID: recordID(for: placeID))
            if !savedIDs.contains(placeID) {
                pendingRemovals.remove(placeID)
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            if !savedIDs.contains(placeID) {
                pendingRemovals.remove(placeID)
            }
        } catch {
            // Silently ignore CloudKit delete failures.
        }
    }
}
