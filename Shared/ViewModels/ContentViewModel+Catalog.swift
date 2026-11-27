import SwiftUI
import Combine
import CoreLocation
import MapKit
import Foundation

extension ContentViewModel {
    // MARK: - Merchant catalog (MerchantElementStore)

    func replaceMerchantCatalog(_ elements: [Element], forceMapRefresh: Bool) {
        merchantStoreRevision = merchantElementStore.replaceAll(elements)
        allElements = merchantElementStore.snapshot()
        if forceMapRefresh {
            self.forceMapRefresh = true
        }
    }

    func replaceOrUpsertMerchant(_ element: Element, forceMapRefresh: Bool) {
        let isNew = merchantElementStore.element(id: element.id) == nil
        merchantStoreRevision = merchantElementStore.upsert(element)
        // Avoid re-materializing the full catalog on single-element updates.
        if isNew {
            allElements.append(element)
        } else if let index = allElements.firstIndex(where: { $0.id == element.id }) {
            allElements[index] = element
        } else {
            allElements = merchantElementStore.snapshot()
        }
        if forceMapRefresh {
            self.forceMapRefresh = true
        }
    }

    func upsertMerchants(_ elements: [Element], forceMapRefresh: Bool) {
        guard !elements.isEmpty else { return }
        merchantStoreRevision = merchantElementStore.upsertMany(elements)
        // Small batches patch the published array in place; large ones snapshot once.
        if elements.count <= 32 {
            for element in elements {
                if let index = allElements.firstIndex(where: { $0.id == element.id }) {
                    allElements[index] = element
                } else {
                    allElements.append(element)
                }
            }
        } else {
            allElements = merchantElementStore.snapshot()
        }
        if forceMapRefresh {
            self.forceMapRefresh = true
        }
    }

    func normalizedMerchantName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    /// User-initiated merchant refresh (pull-to-refresh / empty-state retry).
    /// Reuses repository in-flight coalescing.
    func refreshMerchantData(userInitiated: Bool = true, completion: (@MainActor @Sendable () -> Void)? = nil) {
        if userInitiated {
            merchantSyncFailed = false
            merchantSyncStatusMessage = nil
        }
        fetchElements(warmupOnly: false, forceNetworkRefresh: userInitiated, completion: completion)
    }

    @MainActor
    func refreshMerchantData() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refreshMerchantData(userInitiated: true) {
                continuation.resume()
            }
        }
    }

    var lastSuccessfulSyncRelativeDescription: String? {
        lastSuccessfulSyncAt?.formatted(.relative(presentation: .named))
    }

    // Fetch elements using the APIManager and update the published elements property.
    // `warmupOnly` preloads merchant data without triggering onboarding-hostile side effects.
    // `forceNetworkRefresh` always joins a repository network refresh (pull-to-refresh /
    // retry) and never takes the "warm cache only" early return.
    func fetchElements(warmupOnly: Bool = false, forceNetworkRefresh: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
        Debug.log("fetchElements() called - current state: isLoading=\(isLoading), appState=\(appState), isInitialStartup=\(isInitialStartup), warmupOnly=\(warmupOnly), forceNetworkRefresh=\(forceNetworkRefresh)")
        Debug.logTiming("data", "fetchElements invoked (warmupOnly=\(warmupOnly), forceNetworkRefresh=\(forceNetworkRefresh), allElements=\(allElements.count), isLoading=\(isLoading))")
        
        Task { @MainActor [weak self] in
            guard let self else { return }

            // User-initiated pull joins any in-flight repository refresh via coalescing
            // instead of dismissing the spinner immediately.
            if self.isLoading {
                if forceNetworkRefresh {
                    Debug.log("Already loading; joining in-flight repository refresh for user pull")
                    self.btcMapRepository.refreshElements { [weak self] elements in
                        Task { @MainActor [weak self] in
                            guard let self else {
                                completion?()
                                return
                            }
                            self.applyRepositoryRefreshResult(
                                elements: elements,
                                hadAnyCache: self.btcMapRepository.hasCachedData() || !self.allElements.isEmpty,
                                currentElementsEmpty: self.allElements.isEmpty
                            )
                            // Do not clear isLoading here — the original owner owns that flag.
                            completion?()
                        }
                    }
                } else {
                    Debug.log("Already loading, skipping duplicate call")
                    completion?()
                }
                return
            }
            
            self.isLoading = true

            // Prefer showing cache immediately when memory is empty, even on forced
            // network refresh, so pull-to-refresh does not blank the list.
            if self.allElements.isEmpty,
               let cachedElements = self.btcMapRepository.loadCachedElements(),
               !cachedElements.isEmpty {
                Debug.logCache("Loading \(cachedElements.count) elements from cache into memory")
                Debug.logTiming("data", "loaded \(cachedElements.count) cached elements into memory")
                self.replaceMerchantCatalog(cachedElements, forceMapRefresh: false)
                self.hasLoadedInitialData = true
                self.merchantSyncFailed = false
                self.refreshLastSuccessfulSyncAtFromRepository()
                let cachedHasPlaceholders = self.hasPlaceholderNames(in: cachedElements)

                // Warm cache without placeholders: only skip the network when this is
                // NOT a user-forced refresh (launch / warmup path).
                if !forceNetworkRefresh, !cachedHasPlaceholders {
                    self.isLoading = false
                    self.scheduleCommunityPrefetchIfNeeded()
                    completion?()

                    guard !warmupOnly else {
                        Debug.log("Warmup fetch loaded cached data; skipping map centering and location prompt")
                        return
                    }

                    if let userLoc = self.userLocation {
                        Debug.logMap("Centering map to user location for returning user")
                        self.centerMap(to: userLoc.coordinate)
                    } else {
                        Debug.logMap("No user location yet - requesting location for returning user")
                        self.requestWhenInUseLocationPermission()
                    }

                    if self.isInitialStartup {
                        Debug.log("Initial startup - delaying background updates by 5 seconds")
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .seconds(5))
                            self?.checkForUpdatesInBackground()
                        }
                    } else {
                        self.checkForUpdatesInBackground()
                    }
                    return
                }

                if cachedHasPlaceholders {
                    Debug.logAPI("Cached elements include incomplete names; performing immediate refresh")
                    Debug.logTiming("data", "cached elements contain incomplete names; starting immediate refresh")
                } else {
                    Debug.logAPI("User-forced refresh with warm cache; hitting repository network path")
                }
            }

            let hadAnyCache = self.btcMapRepository.hasCachedData() || !self.allElements.isEmpty
            let currentElementsEmpty = self.allElements.isEmpty
            Debug.logCache("Repository cache available before refresh: \(hadAnyCache)")
            Debug.logCache("Current allElements empty: \(currentElementsEmpty)")
            Debug.logTiming("data", "starting repository refresh (hadCache=\(hadAnyCache), currentEmpty=\(currentElementsEmpty), warmupOnly=\(warmupOnly), forceNetworkRefresh=\(forceNetworkRefresh))")

            self.btcMapRepository.refreshElements { [weak self] elements in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.applyRepositoryRefreshResult(
                        elements: elements,
                        hadAnyCache: hadAnyCache,
                        currentElementsEmpty: currentElementsEmpty
                    )
                    self.isLoading = false
                    self.scheduleCommunityPrefetchIfNeeded()
                    completion?()
                    
                    if self.isInitialStartup {
                        self.isInitialStartup = false
                    }
                }
            }
        }
    }

    private func applyRepositoryRefreshResult(
        elements: [Element]?,
        hadAnyCache: Bool,
        currentElementsEmpty: Bool
    ) {
        let refreshedElements = elements ?? []
        Debug.logAPI("Repository refresh returned \(refreshedElements.count) elements")
        Debug.logTiming("data", "repository refresh completed with \(refreshedElements.count) elements")

        if !refreshedElements.isEmpty {
            Debug.logMap("Setting allElements to repository snapshot (\(refreshedElements.count) elements)")
            replaceMerchantCatalog(refreshedElements, forceMapRefresh: true)
            hasLoadedInitialData = true
            noteMerchantSyncSucceeded()
        } else if currentElementsEmpty && !hadAnyCache {
            Debug.log("Repository returned no data and no cache was available")
            hasLoadedInitialData = true
            noteMerchantSyncOutcome(receivedCount: 0, hadCache: false, storeEmpty: true)
        } else {
            Debug.log("Repository returned no updates - keeping existing \(allElements.count) elements")
            // Empty payload with existing cache usually means "no changes", not failure.
            noteMerchantSyncOutcome(
                receivedCount: 0,
                hadCache: hadAnyCache,
                storeEmpty: allElements.isEmpty
            )
            if !allElements.isEmpty {
                refreshLastSuccessfulSyncAtFromRepository()
            }
        }
    }

    private func noteMerchantSyncSucceeded() {
        merchantSyncFailed = false
        merchantSyncStatusMessage = nil
        // Prefer the repository's just-written sync timestamp when present; fall
        // back to wall-clock so the footer never rewinds to a stale cached value.
        if let iso = btcMapRepository.lastSuccessfulSyncAtISO8601(),
           let parsed = BTCMapDateParser.parse(iso) {
            lastSuccessfulSyncAt = parsed
        } else {
            lastSuccessfulSyncAt = Date.now
        }
    }

    private func noteMerchantSyncOutcome(receivedCount: Int, hadCache: Bool, storeEmpty: Bool) {
        if storeEmpty && receivedCount == 0 && !hadCache {
            merchantSyncFailed = true
            merchantSyncStatusMessage = String(
                localized: "Couldn’t update merchants. Check your connection and try again.",
                comment: "Empty-state message when merchant sync fails with no cache"
            )
        } else {
            merchantSyncFailed = false
            if storeEmpty {
                merchantSyncStatusMessage = nil
            }
        }
    }

    func refreshLastSuccessfulSyncAtFromRepository() {
        guard let iso = btcMapRepository.lastSuccessfulSyncAtISO8601() else { return }
        if let parsed = BTCMapDateParser.parse(iso) {
            lastSuccessfulSyncAt = parsed
        }
    }

    private func hasPlaceholderNames(in elements: [Element]) -> Bool {
        elements.contains { element in
            let rawName = element.osmJSON?.tags?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Element.isInvalidPrimaryName(rawName)
        }
    }

    private func scheduleCommunityPrefetchIfNeeded() {
        guard !hasScheduledCommunityPrefetch else { return }
        hasScheduledCommunityPrefetch = true

        communityPrefetchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Debug.logAPI("Prefetching community datasets in background")
            self.ensureCommunityMapAreasLoaded()
        }
        communityPrefetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // Background update check that doesn't block UI
    private func checkForUpdatesInBackground() {
        Debug.log("Starting background update check")

        btcMapRepository.refreshElements { [weak self] elements in
            DispatchQueue.main.async {
                guard let self = self else { return }

                let refreshedElements = elements ?? []

                if !refreshedElements.isEmpty {
                    Debug.logMap("Background update: Repository returned \(refreshedElements.count) elements")
                    self.replaceMerchantCatalog(refreshedElements, forceMapRefresh: true)
                } else {
                    Debug.log("Background update: No new data available")
                    self.refreshLastSuccessfulSyncAtFromRepository()
                }
            }
        }
    }
}
