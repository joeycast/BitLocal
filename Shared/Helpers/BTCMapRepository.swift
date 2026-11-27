import Foundation

final class BTCMapRepository: BTCMapRepositoryProtocol, @unchecked Sendable {
    static let shared = BTCMapRepository()
    static let epochISO8601 = "1970-01-01T00:00:00Z"

    private let v2Client = BTCMapV2Client()
    private let v2AreasClient = BTCMapV2AreasClient()
    private let v3Client = BTCMapV3AreasClient()
    private let v4Client: BTCMapV4ClientProtocol
    private let userDefaults: UserDefaults
    private let cacheDirectory: URL
    private let modeKey = "btcmap_data_source_mode"
    private let lastAppVersionKey = "btcmap_last_app_version"
    private let cacheIOQueue = DispatchQueue(label: "app.bitlocal.btcmap-cache-io", qos: .utility)
    private let refreshStateQueue = DispatchQueue(label: "app.bitlocal.btcmap-refresh-state", qos: .userInitiated)
    private var isV4RefreshInFlight = false
    private var pendingV4RefreshCompletions: [@Sendable ([Element]?) -> Void] = []

    init(
        v4Client: BTCMapV4ClientProtocol = BTCMapV4Client(),
        userDefaults: UserDefaults = .standard,
        cacheDirectory: URL = .cachesDirectory
    ) {
        self.v4Client = v4Client
        self.userDefaults = userDefaults
        self.cacheDirectory = cacheDirectory
        // Ensure v2 version-change side effects still run (APIManager.init).
        _ = APIManager.shared
        clearV4CacheIfAppVersionChanged()
    }

    /// Clears v4 on-disk cache when the app marketing version changes so
    /// migrations / mapping changes are not stuck on stale JSON.
    private func clearV4CacheIfAppVersionChanged() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let storedVersion = userDefaults.string(forKey: lastAppVersionKey)
        guard storedVersion != currentVersion else { return }

        // storedVersion == nil covers both fresh installs (clear is a no-op) and
        // upgrades from builds that predate version tracking (clear is required).
        if let storedVersion {
            Debug.logCache("App version changed from \(storedVersion) to \(currentVersion); clearing v4 merchant cache")
        } else {
            Debug.logCache("Recording app version \(currentVersion); clearing any pre-tracking v4 merchant cache")
        }
        cacheIOQueue.sync {
            try? FileManager.default.removeItem(at: v4ElementsFileURL)
            try? FileManager.default.removeItem(at: v4SyncStateFileURL)
        }
        userDefaults.set(currentVersion, forKey: lastAppVersionKey)
    }

    private var v4ElementsFileURL: URL {
        cacheDirectory.appending(path: "btcmap_elements_v4.json")
    }

    private var v4SyncStateFileURL: URL {
        cacheDirectory.appending(path: "btcmap_v4_sync_state.json")
    }

    func loadCachedElements() -> [Element]? {
        switch dataSourceMode {
        case .v2Legacy:
            return v2Client.loadCachedElements()
        case .v4Preferred:
            return loadV4Elements()
        case .auto:
            return loadV4Elements() ?? v2Client.loadCachedElements()
        }
    }

    func hasCachedData() -> Bool {
        switch dataSourceMode {
        case .v2Legacy:
            return v2Client.hasCachedData()
        case .v4Preferred:
            return hasV4CachedData()
        case .auto:
            return hasV4CachedData() || v2Client.hasCachedData()
        }
    }

    func lastSuccessfulSyncAtISO8601() -> String? {
        let state = loadV4SyncState()
        if let value = state.lastSuccessfulSyncAt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        // Fall back to incremental anchor / snapshot time when lastSuccessfulSyncAt
        // was not recorded (older caches).
        if let anchor = state.incrementalAnchorUpdatedSince?.trimmingCharacters(in: .whitespacesAndNewlines),
           !anchor.isEmpty {
            return anchor
        }
        return Self.rfc1123ToISO8601(state.snapshotLastModifiedRFC1123)
    }

    func refreshElements(completion: @escaping @Sendable ([Element]?) -> Void) {
        switch dataSourceMode {
        case .v2Legacy:
            Debug.logAPI("BTCMapRepository: using v2 legacy mode")
            v2Client.refreshElements(completion: completion)
        case .v4Preferred:
            Debug.logAPI("BTCMapRepository: using v4 preferred mode")
            refreshV4(allowV2Fallback: false, completion: completion)
        case .auto:
            Debug.logAPI("BTCMapRepository: using auto mode (v4 preferred, v2 fallback)")
            refreshV4(allowV2Fallback: true, completion: completion)
        }
    }

    func searchPlaces(query: V4SearchQuery, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        v4Client.searchPlaces(query: query, completion: completion)
    }

    func fetchPlace(id: String, completion: @escaping @Sendable (Result<V4PlaceRecord, Error>) -> Void) {
        v4Client.fetchPlace(id: id, completion: completion)
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping @Sendable (Result<[V4EventRecord], Error>) -> Void) {
        v4Client.fetchEvents(query: query, completion: completion)
    }

    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V3AreaRecord], Error>) -> Void) {
        v3Client.fetchAreas(updatedSince: updatedSince, limit: limit, completion: completion)
    }

    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V2AreaRecord], Error>) -> Void) {
        v2AreasClient.fetchAreas(updatedSince: updatedSince, limit: limit, completion: completion)
    }

    func fetchV3Area(id: Int, completion: @escaping @Sendable (Result<V3AreaRecord, Error>) -> Void) {
        v3Client.fetchArea(id: id, completion: completion)
    }

    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping @Sendable (Result<[V3AreaElementRecord], Error>) -> Void) {
        v3Client.fetchAreaElements(areaID: areaID, updatedSince: updatedSince, limit: limit, completion: completion)
    }

    func fetchPlaceComments(placeID: String, completion: @escaping @Sendable (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        v4Client.fetchPlaceComments(placeID: placeID, completion: completion)
    }

    private var dataSourceMode: BTCMapDataSourceMode {
        guard let raw = userDefaults.string(forKey: modeKey),
              let mode = BTCMapDataSourceMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }

    private func refreshV4(allowV2Fallback: Bool, completion: @escaping @Sendable ([Element]?) -> Void) {
        let shouldStartRefresh = refreshStateQueue.sync { () -> Bool in
            pendingV4RefreshCompletions.append(completion)
            guard !isV4RefreshInFlight else {
                Debug.logTiming("sync", "coalescing refresh onto in-flight v4 sync")
                return false
            }
            isV4RefreshInFlight = true
            return true
        }

        guard shouldStartRefresh else { return }

        let hadV4Cache = hasV4CachedData()
        let finishRefresh: @Sendable ([Element]?) -> Void = { [weak self] elements in
            self?.finishV4Refresh(elements: elements)
        }
        let startIncremental: @Sendable (String?, [Element]?, V4SyncState?) -> Void = { [weak self] initialAnchorOverride, initialExistingOverride, initialSyncStateOverride in
            guard let self else {
                finishRefresh(nil)
                return
            }
            Debug.logTiming("sync", "starting v4 incremental sync (hadCache=\(hadV4Cache))")
            self.performV4IncrementalSync(
                initialAnchorOverride: initialAnchorOverride,
                initialExistingOverride: initialExistingOverride,
                initialSyncStateOverride: initialSyncStateOverride,
                completion: { [weak self] result in
                    switch result {
                    case .success(let elements):
                        Debug.logTiming("sync", "v4 incremental sync completed with \(elements.count) elements")
                        finishRefresh(elements)
                    case .failure(let error):
                        Debug.logAPI("BTCMap v4 incremental sync failed: \(error.localizedDescription)")
                        guard let self else {
                            finishRefresh(nil)
                            return
                        }
                        if allowV2Fallback && !hadV4Cache {
                            self.v2Client.refreshElements(completion: finishRefresh)
                        } else {
                            finishRefresh(self.loadV4Elements() ?? self.v2Client.loadCachedElements())
                        }
                    }
                }
            )
        }

        if !hadV4Cache {
            Debug.logAPI("BTCMapRepository: no v4 cache, bootstrapping snapshot")
            Debug.logTiming("sync", "starting v4 snapshot bootstrap")
            v4Client.fetchSnapshot { [weak self] result in
                guard let self else {
                    completion(nil)
                    return
                }
                switch result {
                case .success(let payload):
                    let fallbackTimestamp = Self.rfc1123ToISO8601(payload.lastModified) ?? Self.currentISO8601()
                    let initialIncrementalAnchor = Self.rfc1123ToISO8601(payload.lastModified) ?? fallbackTimestamp
                    let mapped = payload.records.map { V4PlaceToElementMapper.snapshotRecordToElement($0, fallbackTimestamp: fallbackTimestamp) }
                    Debug.logTiming("sync", "snapshot bootstrap fetched \(mapped.count) records; initial anchor=\(initialIncrementalAnchor)")
                    self.saveV4Elements(mapped, reason: "snapshot-bootstrap")
                    var syncState = self.loadV4SyncState()
                    syncState.snapshotLastModifiedRFC1123 = payload.lastModified
                    // Follow BTC Map's recommended flow: bootstrap from the CDN snapshot,
                    // then incrementally apply only changes newer than the snapshot.
                    syncState.incrementalAnchorUpdatedSince = initialIncrementalAnchor
                    syncState.schemaVersion = V4SyncState.currentSchemaVersion
                    self.saveV4SyncState(syncState)
                    startIncremental(initialIncrementalAnchor, mapped, syncState)
                case .failure(let error):
                    Debug.logAPI("BTCMap v4 snapshot bootstrap failed: \(error.localizedDescription)")
                    if allowV2Fallback {
                        self.v2Client.refreshElements(completion: finishRefresh)
                    } else {
                        finishRefresh(nil)
                    }
                }
            }
            return
        }

        startIncremental(nil, nil, nil)
    }

    private func finishV4Refresh(elements: [Element]?) {
        let completions = refreshStateQueue.sync { () -> [@Sendable ([Element]?) -> Void] in
            let callbacks = pendingV4RefreshCompletions
            pendingV4RefreshCompletions.removeAll()
            isV4RefreshInFlight = false
            return callbacks
        }

        completions.forEach { $0(elements) }
    }

    private func performV4IncrementalSync(
        initialAnchorOverride: String? = nil,
        initialExistingOverride: [Element]? = nil,
        initialSyncStateOverride: V4SyncState? = nil,
        completion: @escaping @Sendable (Result<[Element], Error>) -> Void
    ) {
        let existing = initialExistingOverride ?? loadV4Elements() ?? []
        var syncState = initialSyncStateOverride ?? loadV4SyncState()
        var anchor = initialAnchorOverride
            ?? syncState.incrementalAnchorUpdatedSince
            ?? Self.rfc1123ToISO8601(syncState.snapshotLastModifiedRFC1123)
            ?? Self.epochISO8601
        var maxPages = 20

        if shouldForceFullNameBackfill(existing: existing, syncState: syncState) {
            anchor = Self.epochISO8601
            syncState.incrementalAnchorUpdatedSince = Self.epochISO8601
            maxPages = 200
            Debug.logAPI("BTCMapRepository: forcing one-time full v4 backfill to replace stale merchant names")
        }

        Debug.logTiming("sync", "incremental sync stepper ready (existing=\(existing.count), anchor=\(anchor), maxPages=\(maxPages))")

        runV4IncrementalSyncPage(
            anchor: anchor,
            merged: existing,
            syncState: syncState,
            pageCount: 1,
            maxPages: maxPages,
            completion: completion
        )
    }

    private func runV4IncrementalSyncPage(
        anchor: String,
        merged: [Element],
        syncState: V4SyncState,
        pageCount: Int,
        maxPages: Int,
        completion: @escaping @Sendable (Result<[Element], Error>) -> Void
    ) {
        Debug.logTiming("sync", "requesting incremental page \(pageCount) from anchor \(anchor)")
        v4Client.fetchPlaces(updatedSince: anchor, includeDeleted: true) { [weak self] result in
            guard let self else {
                completion(.success(merged))
                return
            }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let records):
                Debug.logTiming("sync", "received incremental page \(pageCount) with \(records.count) records")
                var nextSyncState = syncState
                if records.isEmpty {
                    nextSyncState.schemaVersion = V4SyncState.currentSchemaVersion
                    nextSyncState.lastSuccessfulSyncAt = Self.currentISO8601()
                    self.saveV4Elements(merged, reason: "incremental-empty-page")
                    self.saveV4SyncState(nextSyncState)
                    completion(.success(merged))
                    return
                }

                let incoming = records.map(V4PlaceToElementMapper.placeRecordToElement)
                let nextMerged = Self.mergeElements(existing: merged, incoming: incoming)
                var nextAnchor = anchor

                if let maxUpdated = records.compactMap({ $0.updatedAt }).max(),
                   self.parseFlexibleDate(maxUpdated) != nil {
                    nextAnchor = maxUpdated
                    nextSyncState.incrementalAnchorUpdatedSince = maxUpdated
                }

                self.saveV4SyncState(nextSyncState)

                if records.count >= 5000 && pageCount < maxPages {
                    self.runV4IncrementalSyncPage(
                        anchor: nextAnchor,
                        merged: nextMerged,
                        syncState: nextSyncState,
                        pageCount: pageCount + 1,
                        maxPages: maxPages,
                        completion: completion
                    )
                } else {
                    nextSyncState.schemaVersion = V4SyncState.currentSchemaVersion
                    nextSyncState.lastSuccessfulSyncAt = Self.currentISO8601()
                    self.saveV4Elements(nextMerged, reason: "incremental-final-page")
                    self.saveV4SyncState(nextSyncState)
                    completion(.success(nextMerged))
                }
            }
        }
    }

    private func shouldForceFullNameBackfill(existing: [Element], syncState: V4SyncState) -> Bool {
        guard syncState.schemaVersion < V4SyncState.currentSchemaVersion else { return false }
        guard !existing.isEmpty else { return false }
        return existing.contains { element in
            let name = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.hasPrefix("BTC Map Place #")
        }
    }

    private func loadV4Elements() -> [Element]? {
        cacheIOQueue.sync {
            loadV4ElementsUnlocked()
        }
    }

    private func loadV4ElementsUnlocked() -> [Element]? {
        do {
            let start = CFAbsoluteTimeGetCurrent()
            let data = try Data(contentsOf: v4ElementsFileURL)
            let readMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let decodeStart = CFAbsoluteTimeGetCurrent()
            let elements = try JSONDecoder().decode([Element].self, from: data)
            let decodeMS = (CFAbsoluteTimeGetCurrent() - decodeStart) * 1000
            Debug.logTiming(
                "sync",
                "loadV4Elements count=\(elements.count) bytes=\(data.count) readMS=\(String(format: "%.1f", readMS)) decodeMS=\(String(format: "%.1f", decodeMS))"
            )
            return elements.isEmpty ? nil : elements
        } catch {
            return nil
        }
    }

    private func saveV4Elements(_ elements: [Element], reason: String = "unspecified") {
        cacheIOQueue.async {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let data = try JSONEncoder().encode(elements)
                let encodeMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let writeStart = CFAbsoluteTimeGetCurrent()
                try data.write(to: self.v4ElementsFileURL, options: .atomic)
                let writeMS = (CFAbsoluteTimeGetCurrent() - writeStart) * 1000
                Debug.logCache(
                    "Saved \(elements.count) v4 elements (\(data.count) bytes) to \(self.v4ElementsFileURL.lastPathComponent) [reason=\(reason)] encodeMS=\(String(format: "%.1f", encodeMS)) writeMS=\(String(format: "%.1f", writeMS))"
                )
                Debug.logTiming(
                    "sync",
                    "saveV4Elements count=\(elements.count) bytes=\(data.count) encodeMS=\(String(format: "%.1f", encodeMS)) writeMS=\(String(format: "%.1f", writeMS)) reason=\(reason)"
                )
            } catch {
                Debug.logCache("Failed to save v4 elements: \(error.localizedDescription)")
            }
        }
    }

    private func hasV4CachedData() -> Bool {
        cacheIOQueue.sync {
            guard FileManager.default.fileExists(atPath: v4ElementsFileURL.path) else { return false }
            return (loadV4ElementsUnlocked()?.isEmpty == false)
        }
    }

    private func loadV4SyncState() -> V4SyncState {
        cacheIOQueue.sync {
            do {
                let data = try Data(contentsOf: v4SyncStateFileURL)
                return try JSONDecoder().decode(V4SyncState.self, from: data)
            } catch {
                return .empty
            }
        }
    }

    private func saveV4SyncState(_ state: V4SyncState) {
        cacheIOQueue.async {
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: self.v4SyncStateFileURL, options: .atomic)
            } catch {
                Debug.logCache("Failed to save v4 sync state: \(error.localizedDescription)")
            }
        }
    }

    static func mergeElements(existing: [Element], incoming: [Element]) -> [Element] {
        var dictionary = IdentifiableIndex.byID(existing)
        for element in incoming {
            let isDeleted = !(element.deletedAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if isDeleted {
                dictionary.removeValue(forKey: element.id)
                continue
            }

            if let current = dictionary[element.id] {
                if shouldPreferIncoming(element, over: current) || isIncomingNewer(element, than: current) {
                    dictionary[element.id] = element
                }
            } else {
                dictionary[element.id] = element
            }
        }
        return Array(dictionary.values)
    }

    private static func shouldPreferIncoming(_ incoming: Element, over current: Element) -> Bool {
        let currentName = current.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let incomingName = incoming.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentIsPlaceholder = currentName.hasPrefix("BTC Map Place #")
        let incomingIsPlaceholder = incomingName.hasPrefix("BTC Map Place #")
        return currentIsPlaceholder && !incomingIsPlaceholder && !incomingName.isEmpty
    }

    private static func isIncomingNewer(_ incoming: Element, than current: Element) -> Bool {
        switch (incoming.updatedAt, current.updatedAt) {
        case let (.some(incomingValue), .some(currentValue)):
            guard let incomingDate = parseStaticFlexibleDate(incomingValue),
                  let currentDate = parseStaticFlexibleDate(currentValue) else {
                return incomingValue >= currentValue
            }
            return incomingDate >= currentDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return true
        }
    }

    private func parseFlexibleDate(_ value: String) -> Date? {
        Self.parseStaticFlexibleDate(value)
    }

    private static func parseStaticFlexibleDate(_ value: String) -> Date? {
        BTCMapDateParser.parse(value)
    }

    private final class LockedRFC1123Parser: @unchecked Sendable {
        private let lock = NSLock()
        private let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return formatter
        }()

        func parse(_ header: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            return formatter.date(from: header)
        }
    }

    private static let rfc1123Parser = LockedRFC1123Parser()

    private static func rfc1123ToISO8601(_ header: String?) -> String? {
        guard let header, let date = rfc1123Parser.parse(header) else { return nil }
        return date.ISO8601Format()
    }

    private static func currentISO8601() -> String {
        Date.now.ISO8601Format()
    }
}
