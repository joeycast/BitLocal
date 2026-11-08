//
//  MerchantStoreBootstrap.swift
//  bitlocal
//
//  Redesign phase 2: the SQLite merchant store runs next to the legacy JSON
//  cache. On first launch it imports the JSON cache (or bootstraps from the
//  CDN snapshot), then syncs from BTC Map v4. Until phase 4 moves the map onto
//  the store, nothing reads from it in Release builds; Debug builds compare
//  its row count with the legacy cache so drift shows up in the log.
//

import Foundation
import os
import BitLocalData
import BitLocalDomain

enum MerchantStoreBootstrap {
    private static let logger = Logger(subsystem: "app.bitlocal", category: "store")
    private static let importedKey = "legacy_json_imported"

    /// Shared store and engine. Created lazily on first use, off the main thread.
    static let environment: (store: MerchantStore, sync: SyncEngine)? = {
        do {
            let store = try MerchantStore(url: try MerchantStore.defaultURL(), categoryTerms: { CategorySearchTerms.shared.terms(for: $0) })
            let client = BTCMapClient(userAgent: BTCMapRequestMetadata.appUserAgent)
            let sync = SyncEngine(store: store, client: client, mapper: .app)
            return (store, sync)
        } catch {
            logger.error("Could not open merchant store: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    /// Imports the legacy cache once, then syncs. Safe to call on every launch and foreground.
    static func run() async {
        guard let environment else { return }
        let store = environment.store
        do {
            if try await store.syncValue(forKey: importedKey) == nil {
                try await importLegacyCache(into: store)
            }
            let result = try await environment.sync.sync()
            logger.info("Store sync: bootstrapped=\(result.bootstrapped) pages=\(result.pages) upserted=\(result.upserted) deleted=\(result.deleted)")
            #if DEBUG
            await compareWithLegacyCache(store: store)
            #endif
        } catch {
            logger.error("Store sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves the legacy `btcmap_elements_v4.json` rows and anchor into SQLite in one transaction.
    /// Idempotent (upsert by id); on failure the partial database is cleared and the
    /// sync engine bootstraps from the CDN snapshot instead.
    private static func importLegacyCache(into store: MerchantStore) async throws {
        let start = ContinuousClock.now
        let elements = BTCMapRepository.shared.loadCachedElements() ?? []
        let merchants = elements.compactMap(\.merchant)
        var state = [importedKey: "1"]
        if !merchants.isEmpty, let anchor = BTCMapRepository.shared.legacyIncrementalAnchor() {
            state[SyncEngine.Key.anchor] = anchor
        }
        do {
            try await store.apply(SyncBatch(upserts: merchants, syncState: state))
            let elapsed = String(describing: start.duration(to: .now))
            logger.info("Imported \(merchants.count) merchants from the JSON cache in \(elapsed, privacy: .public)")
        } catch {
            logger.error("JSON import failed, starting fresh: \(error.localizedDescription, privacy: .public)")
            try await store.removeAll()
            try await store.setSyncValue("1", forKey: importedKey)
        }
    }

    #if DEBUG
    private static func compareWithLegacyCache(store: MerchantStore) async {
        let legacy = BTCMapRepository.shared.loadCachedElements()?.filter { $0.merchantSummary != nil }.count ?? 0
        let current = (try? await store.count()) ?? 0
        if legacy == current {
            logger.debug("Store dual-run: counts match (\(current))")
        } else {
            logger.notice("Store dual-run: store has \(current) merchants, legacy cache has \(legacy)")
        }
    }
    #endif
}
