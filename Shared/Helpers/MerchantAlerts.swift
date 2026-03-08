import CloudKit
import CryptoKit
import MapKit
import Security
import SwiftUI
import UIKit
import UserNotifications

struct CitySubscription: Codable, Hashable, Identifiable {
    let id: UUID
    let cityKey: String
    let city: String
    let region: String
    let country: String
    let displayName: String
    let createdAt: Date
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        cityKey: String,
        city: String,
        region: String,
        country: String,
        displayName: String,
        createdAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.cityKey = cityKey
        self.city = city
        self.region = region
        self.country = country
        self.displayName = displayName
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }

    init(choice: MerchantAlertCityChoice) {
        self.init(
            cityKey: choice.cityKey,
            city: choice.city,
            region: choice.region,
            country: choice.country,
            displayName: choice.displayName
        )
    }
}

struct MerchantAlertCityChoice: Hashable, Identifiable {
    let id = UUID()
    let city: String
    let region: String
    let country: String

    var cityKey: String {
        MerchantAlertsCityNormalizer.cityKey(city: city, region: region, country: country)
    }

    var displayName: String {
        MerchantAlertsCityNormalizer.displayName(city: city, region: region, country: country)
    }
}

struct CityDigest: Codable, Hashable, Identifiable {
    let id: String
    let cityKey: String
    let cityDisplayName: String
    let digestWindowStart: Date?
    let digestWindowEnd: Date?
    let merchantCount: Int
    let merchantIDs: [String]
    let topMerchantNames: [String]

    var summaryLine: String {
        guard !topMerchantNames.isEmpty else {
            return "\(merchantCount) new merchants"
        }

        let headline = topMerchantNames.prefix(2).joined(separator: ", ")
        if merchantCount > topMerchantNames.count {
            return "\(headline), and more"
        }
        return headline
    }
}

enum MerchantAlertsCityNormalizer {
    static func cityKey(city: String, region: String, country: String) -> String {
        [city, region, country]
            .map(normalizeComponent)
            .joined(separator: "|")
    }

    static func displayName(city: String, region: String, country: String) -> String {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)

        let secondaryParts = [trimmedRegion, trimmedCountry].filter { !$0.isEmpty }
        if secondaryParts.isEmpty {
            return trimmedCity
        }
        return "\(trimmedCity), \(secondaryParts.joined(separator: ", "))"
    }

    private static func normalizeComponent(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        return folded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

@MainActor
final class MerchantAlertsManager: NSObject, ObservableObject {
    static let shared = MerchantAlertsManager()

    @Published private(set) var subscriptions: [CitySubscription] = []
    @Published private(set) var notificationSettings: UNNotificationSettings?
    @Published private(set) var cloudKitAccountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var isRefreshingStatus = false
    @Published var activeDigest: CityDigest?
    @Published var lastDigest: CityDigest?
    @Published var errorMessage: String?

    private let userDefaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let subscriptionsKey = "merchant_alert_subscriptions_v1"
    private let lastDigestKey = "merchant_alert_last_digest_v1"
    private let keychainService = "app.bitlocal.bitlocal.merchant-alerts"
    private let keychainSubscriptionsAccount = "merchant_alert_subscriptions_v1"
    private let digestRecordType = "CityDigest"
    private let localNotificationKindKey = "merchant_alert_kind"
    private let localNotificationDigestRecordNameKey = "merchant_alert_digest_record_name"
    private let localNotificationKindDigest = "city_digest"

    var currentSubscription: CitySubscription? {
        subscriptions.first(where: \.isEnabled)
    }

    var isCloudKitAvailable: Bool {
        cloudKitAccountStatus == .available
    }

    var notificationsAuthorized: Bool {
        guard let notificationSettings else { return false }
        return notificationSettings.authorizationStatus == .authorized || notificationSettings.authorizationStatus == .provisional
    }

    var canEnableAlerts: Bool {
        isCloudKitAvailable && (notificationSettings?.authorizationStatus != .denied)
    }

    var cloudKitStatusSummary: String {
        switch cloudKitAccountStatus {
        case .available:
            return "Signed in to iCloud"
        case .noAccount:
            return "Sign in to iCloud to enable merchant alerts."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable."
        case .couldNotDetermine:
            return "Checking iCloud status…"
        @unknown default:
            return "BitLocal could not determine your iCloud status."
        }
    }

    private override init() {
        self.userDefaults = .standard
        self.notificationCenter = .current()

        let configuredIdentifier = (Bundle.main.object(forInfoDictionaryKey: "BitLocalCloudKitContainerIdentifier") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if configuredIdentifier.isEmpty {
            self.container = CKContainer.default()
        } else {
            self.container = CKContainer(identifier: configuredIdentifier)
        }
        self.publicDatabase = container.publicCloudDatabase

        super.init()
        loadPersistedState()
    }

    func refreshStatus() async {
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        do {
            cloudKitAccountStatus = try await container.merchantAlertsAccountStatus()
        } catch {
            cloudKitAccountStatus = .couldNotDetermine
            errorMessage = error.localizedDescription
        }

        notificationSettings = await notificationCenter.merchantAlertsSettings()

        if subscriptions.isEmpty, isCloudKitAvailable {
            await restoreSubscriptionsFromCloudKitIfNeeded()
        }

        if notificationsAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func enableNotifications(for choice: MerchantAlertCityChoice) async {
        errorMessage = nil

        await refreshStatus()
        guard isCloudKitAvailable else { return }

        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            errorMessage = "BitLocal needs notification permission to send city alerts."
            return
        }

        let subscription = CitySubscription(choice: choice)

        do {
            if let previous = currentSubscription, previous.cityKey != subscription.cityKey {
                try await deleteCloudKitSubscription(for: previous)
            }

            try await saveCloudKitSubscription(for: subscription)
            subscriptions = [subscription]
            persistSubscriptions()
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }

        await refreshStatus()
    }

    func disableNotifications() async {
        errorMessage = nil

        if let subscription = currentSubscription {
            do {
                try await deleteCloudKitSubscription(for: subscription)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        subscriptions = []
        persistSubscriptions()
        activeDigest = nil
        lastDigest = nil
        userDefaults.removeObject(forKey: lastDigestKey)
        await refreshStatus()
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await notificationCenter.merchantAlertsSettings()
        notificationSettings = settings

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        case .notDetermined, .ephemeral:
            do {
                let granted = try await notificationCenter.merchantAlertsRequestAuthorization(options: [.alert, .badge, .sound])
                notificationSettings = await notificationCenter.merchantAlertsSettings()
                return granted
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        @unknown default:
            return false
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func presentLastDigest() {
        guard let lastDigest else { return }
        activeDigest = lastDigest
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        do {
            guard let digest = try await digest(from: userInfo) else {
                return .noData
            }
            lastDigest = digest
            persistLastDigest()

            if UIApplication.shared.applicationState == .active {
                activeDigest = digest
            } else {
                try await scheduleLocalNotification(for: digest)
            }
            return .newData
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    func handleNotificationResponse(userInfo: [AnyHashable: Any]) async {
        do {
            guard let digest = try await digest(from: userInfo) else { return }
            lastDigest = digest
            persistLastDigest()
            activeDigest = digest
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPersistedState() {
        if let data = loadPersistedSubscriptionsData(),
           let decoded = try? JSONDecoder().decode([CitySubscription].self, from: data) {
            subscriptions = decoded
        }

        if let data = userDefaults.data(forKey: lastDigestKey),
           let decoded = try? JSONDecoder().decode(CityDigest.self, from: data) {
            lastDigest = decoded
        }
    }

    private func persistSubscriptions() {
        guard !subscriptions.isEmpty else {
            clearPersistedSubscriptions()
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(subscriptions) {
            userDefaults.set(data, forKey: subscriptionsKey)
            saveSubscriptionsToKeychain(data)
        } else {
            clearPersistedSubscriptions()
        }
    }

    private func persistLastDigest() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(lastDigest) {
            userDefaults.set(data, forKey: lastDigestKey)
        }
    }

    private func saveCloudKitSubscription(for subscription: CitySubscription) async throws {
        let predicate = NSPredicate(format: "cityKey == %@", subscription.cityKey)
        let querySubscription = CKQuerySubscription(
            recordType: digestRecordType,
            predicate: predicate,
            subscriptionID: cloudKitSubscriptionID(for: subscription.cityKey),
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        querySubscription.notificationInfo = notificationInfo

        _ = try await publicDatabase.merchantAlertsSaveSubscription(querySubscription)
    }

    private func deleteCloudKitSubscription(for subscription: CitySubscription) async throws {
        _ = try await publicDatabase.merchantAlertsDeleteSubscription(withID: cloudKitSubscriptionID(for: subscription.cityKey))
    }

    private func fetchDigest(recordID: CKRecord.ID) async throws -> CityDigest {
        let record = try await publicDatabase.merchantAlertsRecord(for: recordID)
        return try CityDigest(record: record)
    }

    private func digest(from userInfo: [AnyHashable: Any]) async throws -> CityDigest? {
        if let kind = userInfo[localNotificationKindKey] as? String,
           kind == localNotificationKindDigest,
           let recordName = userInfo[localNotificationDigestRecordNameKey] as? String {
            return try await fetchDigest(recordID: CKRecord.ID(recordName: recordName))
        }

        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = notification as? CKQueryNotification,
              let recordID = queryNotification.recordID else {
            return nil
        }

        return try await fetchDigest(recordID: recordID)
    }

    private func scheduleLocalNotification(for digest: CityDigest) async throws {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: digest)
        content.body = notificationBody(for: digest)
        content.sound = .default
        content.userInfo = [
            localNotificationKindKey: localNotificationKindDigest,
            localNotificationDigestRecordNameKey: digest.id
        ]

        let identifier = "merchant-alert-\(digest.id)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await notificationCenter.merchantAlertsAdd(request)
    }

    private func notificationTitle(for digest: CityDigest) -> String {
        let city = digest.cityDisplayName.components(separatedBy: ",").first ?? digest.cityDisplayName
        if digest.merchantCount == 1 {
            return "New merchant in \(city)"
        }
        return "New merchants in \(city)"
    }

    private func notificationBody(for digest: CityDigest) -> String {
        let names = Array(digest.topMerchantNames.prefix(2))

        switch names.count {
        case 2 where digest.merchantCount > 2:
            return "\(names[0]), \(names[1]), and \(digest.merchantCount - 2) more now accept bitcoin."
        case 2:
            return "\(names[0]) and \(names[1]) now accept bitcoin."
        case 1 where digest.merchantCount > 1:
            return "\(names[0]) and \(digest.merchantCount - 1) more now accept bitcoin."
        case 1:
            return "\(names[0]) now accepts bitcoin."
        default:
            return "\(digest.merchantCount) new merchants now accept bitcoin."
        }
    }

    private func cloudKitSubscriptionID(for cityKey: String) -> String {
        let digest = SHA256.hash(data: Data(cityKey.utf8))
        let hashed = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "city-digest-\(hashed)"
    }

    private func restoreSubscriptionsFromCloudKitIfNeeded() async {
        do {
            let allSubscriptions = try await publicDatabase.merchantAlertsFetchAllSubscriptions()
            let querySubscriptions = allSubscriptions.compactMap { $0 as? CKQuerySubscription }

            guard let querySubscription = querySubscriptions.first(where: { $0.recordType == digestRecordType }),
                  let cityKey = extractCityKey(from: querySubscription) else {
                return
            }

            let restored = CitySubscription(
                cityKey: cityKey,
                city: prettifyCityKeyComponent(cityKey, index: 0),
                region: prettifyCityKeyComponent(cityKey, index: 1),
                country: prettifyCityKeyComponent(cityKey, index: 2),
                displayName: prettifyDisplayName(from: cityKey)
            )

            subscriptions = [restored]
            persistSubscriptions()
        } catch {
            Debug.log("Merchant alert CloudKit subscription restore failed: \(error.localizedDescription)")
        }
    }

    private func extractCityKey(from subscription: CKQuerySubscription) -> String? {
        let format = subscription.predicate.predicateFormat
        let matches = format.matches(of: /"([^"]+)"/)
        guard let last = matches.last else { return nil }
        return String(last.1)
    }

    private func prettifyCityKeyComponent(_ cityKey: String, index: Int) -> String {
        let parts = cityKey.split(separator: "|").map(String.init)
        guard parts.indices.contains(index) else { return "" }
        return prettifyComponent(parts[index])
    }

    private func prettifyDisplayName(from cityKey: String) -> String {
        cityKey
            .split(separator: "|")
            .map { prettifyComponent(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func prettifyComponent(_ component: String) -> String {
        let uppercaseShortForms: Set<String> = [
            "al", "ak", "az", "ar", "ca", "co", "ct", "dc", "de", "fl", "ga", "hi", "ia", "id",
            "il", "in", "ks", "ky", "la", "ma", "md", "me", "mi", "mn", "mo", "ms", "mt", "nc",
            "nd", "ne", "nh", "nj", "nm", "nv", "ny", "oh", "ok", "or", "pa", "ri", "sc", "sd",
            "tn", "tx", "ut", "va", "vt", "wa", "wi", "wv", "wy", "uk", "uae", "usa", "us"
        ]

        return component
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if uppercaseShortForms.contains(lower) {
                    return lower.uppercased()
                }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func loadPersistedSubscriptionsData() -> Data? {
        if let data = userDefaults.data(forKey: subscriptionsKey) {
            return data
        }
        return loadSubscriptionsFromKeychain()
    }

    private func loadSubscriptionsFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainSubscriptionsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func saveSubscriptionsToKeychain(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainSubscriptionsAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            Debug.log("Merchant alert keychain update failed with status \(updateStatus)")
            return
        }

        var createQuery = query
        createQuery[kSecValueData as String] = data
        let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
        if createStatus != errSecSuccess {
            Debug.log("Merchant alert keychain add failed with status \(createStatus)")
        }
    }

    private func clearPersistedSubscriptions() {
        userDefaults.removeObject(forKey: subscriptionsKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainSubscriptionsAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

extension CityDigest {
    init(record: CKRecord) throws {
        guard let cityKey = record["cityKey"] as? String else {
            throw MerchantAlertsError.invalidDigestRecord
        }

        self.id = record.recordID.recordName
        self.cityKey = cityKey
        self.cityDisplayName = (record["cityDisplayName"] as? String) ?? cityKey
        self.digestWindowStart = record["digestWindowStart"] as? Date
        self.digestWindowEnd = record["digestWindowEnd"] as? Date
        self.merchantCount = Int((record["merchantCount"] as? Int64) ?? 0)
        self.merchantIDs = (record["merchantIDs"] as? [String]) ?? []
        self.topMerchantNames = (record["topMerchantNames"] as? [String]) ?? []
    }
}

enum MerchantAlertsError: LocalizedError {
    case invalidDigestRecord

    var errorDescription: String? {
        switch self {
        case .invalidDigestRecord:
            return "BitLocal received an incomplete city digest from CloudKit."
        }
    }
}

final class BitLocalAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Debug.log("Registered for remote notifications with token: \(token)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Debug.log("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let result = await MerchantAlertsManager.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(result)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MerchantAlertsManager.shared.handleNotificationResponse(
            userInfo: response.notification.request.content.userInfo
        )
    }
}

private extension UNUserNotificationCenter {
    func merchantAlertsRequestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func merchantAlertsSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    func merchantAlertsAdd(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private extension CKContainer {
    func merchantAlertsAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

private extension CKDatabase {
    func merchantAlertsSaveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            save(subscription) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let saved {
                    continuation.resume(returning: saved)
                } else {
                    continuation.resume(throwing: MerchantAlertsError.invalidDigestRecord)
                }
            }
        }
    }

    func merchantAlertsDeleteSubscription(withID subscriptionID: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            delete(withSubscriptionID: subscriptionID) { deletedID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let deletedID {
                    continuation.resume(returning: deletedID)
                } else {
                    continuation.resume(returning: subscriptionID)
                }
            }
        }
    }

    func merchantAlertsRecord(for recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: MerchantAlertsError.invalidDigestRecord)
                }
            }
        }
    }

    func merchantAlertsFetchAllSubscriptions() async throws -> [CKSubscription] {
        try await withCheckedThrowingContinuation { continuation in
            fetchAllSubscriptions { subscriptions, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: subscriptions ?? [])
                }
            }
        }
    }
}
