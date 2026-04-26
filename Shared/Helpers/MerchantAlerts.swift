import CloudKit
import CryptoKit
import MapKit
import Security
import SwiftUI
import UIKit
import UserNotifications

struct CitySubscription: Codable, Hashable, Identifiable {
    let id: UUID
    let locationID: String
    let cityKey: String
    let city: String
    let region: String
    let country: String
    let displayName: String
    let createdAt: Date
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        locationID: String,
        cityKey: String,
        city: String,
        region: String,
        country: String,
        displayName: String,
        createdAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.locationID = locationID
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
            locationID: choice.locationID,
            cityKey: choice.cityKey,
            city: choice.city,
            region: choice.region,
            country: choice.country,
            displayName: choice.displayName
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cityKey = try container.decodeIfPresent(String.self, forKey: .cityKey) ?? ""
        locationID = try container.decodeIfPresent(String.self, forKey: .locationID) ?? cityKey
        city = try container.decode(String.self, forKey: .city)
        region = try container.decode(String.self, forKey: .region)
        country = try container.decode(String.self, forKey: .country)
        displayName = try container.decode(String.self, forKey: .displayName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

struct MerchantAlertCityChoice: Hashable, Identifiable {
    let locationID: String
    let city: String
    let region: String
    let country: String

    var id: String {
        locationID
    }

    var cityKey: String {
        MerchantAlertsCityNormalizer.cityKey(city: city, region: region, country: country)
    }

    var displayName: String {
        MerchantAlertsCityNormalizer.displayName(city: city, region: region, country: country)
    }
}

struct CityDigest: Codable, Hashable, Identifiable {
    let id: String
    let locationID: String?
    let cityKey: String
    let cityDisplayName: String
    let digestWindowStart: Date?
    let digestWindowEnd: Date?
    let merchantCount: Int
    let merchantIDs: [String]
    let topMerchantNames: [String]
    let timeZoneID: String?
    let deliveryLocalDate: String?

    var summaryLine: String {
        guard !topMerchantNames.isEmpty else {
            return String(format: NSLocalizedString("%lld new merchants", comment: "Summary line for a digest with no merchant names"), merchantCount)
        }

        let headline = topMerchantNames.prefix(2).joined(separator: ", ")
        if merchantCount > topMerchantNames.count {
            return String(format: NSLocalizedString("%@, and more", comment: "Summary line that appends and more to merchant names"), headline)
        }
        return headline
    }
}

enum MerchantAlertsCityNormalizer {
    private static let unitedStatesRegionAliases: [String: String] = [
        "al": "Alabama",
        "ak": "Alaska",
        "az": "Arizona",
        "ar": "Arkansas",
        "ca": "California",
        "co": "Colorado",
        "ct": "Connecticut",
        "de": "Delaware",
        "dc": "District of Columbia",
        "fl": "Florida",
        "ga": "Georgia",
        "hi": "Hawaii",
        "id": "Idaho",
        "il": "Illinois",
        "in": "Indiana",
        "ia": "Iowa",
        "ks": "Kansas",
        "ky": "Kentucky",
        "la": "Louisiana",
        "me": "Maine",
        "md": "Maryland",
        "ma": "Massachusetts",
        "mi": "Michigan",
        "mn": "Minnesota",
        "ms": "Mississippi",
        "mo": "Missouri",
        "mt": "Montana",
        "ne": "Nebraska",
        "nv": "Nevada",
        "nh": "New Hampshire",
        "nj": "New Jersey",
        "nm": "New Mexico",
        "ny": "New York",
        "nc": "North Carolina",
        "nd": "North Dakota",
        "oh": "Ohio",
        "ok": "Oklahoma",
        "or": "Oregon",
        "pa": "Pennsylvania",
        "ri": "Rhode Island",
        "sc": "South Carolina",
        "sd": "South Dakota",
        "tn": "Tennessee",
        "tx": "Texas",
        "ut": "Utah",
        "vt": "Vermont",
        "va": "Virginia",
        "wa": "Washington",
        "wv": "West Virginia",
        "wi": "Wisconsin",
        "wy": "Wyoming"
    ]

    static func cityKey(city: String, region: String, country: String) -> String {
        let canonicalCountry = canonicalCountry(country)
        let canonicalRegion = canonicalRegion(region, country: canonicalCountry)

        return [city, canonicalRegion, canonicalCountry]
            .map(normalizeComponent)
            .joined(separator: "|")
    }

    static func normalizedSearchText(_ raw: String) -> String {
        normalizeComponent(raw)
    }

    static func displayName(city: String, region: String, country: String) -> String {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = canonicalCountry(country)
        let trimmedRegion = canonicalRegion(region, country: trimmedCountry)

        let secondaryParts = [trimmedRegion, trimmedCountry].filter { !$0.isEmpty }
        if secondaryParts.isEmpty {
            return trimmedCity
        }
        return "\(trimmedCity), \(secondaryParts.joined(separator: ", "))"
    }

    static func normalizedComponent(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        return folded
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizeComponent(_ raw: String) -> String {
        normalizedComponent(raw)
    }

    private static func canonicalCountry(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalRegion(_ raw: String, country: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let normalizedCountry = normalizedComponent(country)
        if normalizedCountry == "united states" || normalizedCountry == "usa" || normalizedCountry == "us" {
            let normalizedRegion = normalizedComponent(trimmed)
            if let alias = unitedStatesRegionAliases[normalizedRegion] {
                return alias
            }
        }

        return trimmed
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
    private let digestCatchUpLimit = 1
    private var hasRegisteredForRemoteNotifications = false
    private var isRegisteringForRemoteNotifications = false

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
            return NSLocalizedString("Signed in to iCloud", comment: "Status text when iCloud is available for merchant alerts")
        case .noAccount:
            return NSLocalizedString("Sign in to iCloud in Settings to turn on alerts.", comment: "Status text prompting the user to sign in to iCloud")
        case .restricted:
            return NSLocalizedString("iCloud isn't available on this device.", comment: "Status text when iCloud is unavailable on device")
        case .temporarilyUnavailable:
            return NSLocalizedString("iCloud is temporarily unavailable. Try again in a bit.", comment: "Status text when iCloud is temporarily unavailable")
        case .couldNotDetermine:
            return NSLocalizedString("Checking iCloud…", comment: "Status text while checking iCloud availability")
        @unknown default:
            return NSLocalizedString("Something went wrong checking iCloud. Try again later.", comment: "Status text when iCloud availability check fails")
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

        registerForRemoteNotificationsIfNeeded()
        await catchUpMissedDigestIfNeeded()
    }

    func enableNotifications(for choice: MerchantAlertCityChoice) async {
        errorMessage = nil

        await refreshStatus()
        guard isCloudKitAvailable else { return }

        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            errorMessage = NSLocalizedString("BitLocal needs permission to send you notifications. You can turn this on in Settings.", comment: "Error shown when notification permissions are denied")
            return
        }

        let subscription = CitySubscription(choice: choice)

        do {
            if let previous = currentSubscription, previous.locationID != subscription.locationID {
                try await deleteCloudKitSubscription(for: previous)
            }

            try await saveCloudKitSubscription(for: subscription)
            subscriptions = [subscription]
            persistSubscriptions()
            registerForRemoteNotificationsIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            Debug.log("Merchant alerts: failed to enable notifications for \(subscription.locationID): \(error.localizedDescription)")
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
            }

            try await scheduleLocalNotification(for: digest)
            return .newData
        } catch {
            errorMessage = error.localizedDescription
            Debug.log("Merchant alerts: failed handling remote notification: \(error.localizedDescription)")
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
            Debug.log("Merchant alerts: failed handling notification response: \(error.localizedDescription)")
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
        let predicate = NSPredicate(format: "locationID == %@", subscription.locationID)
        let querySubscription = CKQuerySubscription(
            recordType: digestRecordType,
            predicate: predicate,
            subscriptionID: cloudKitSubscriptionID(for: subscription.locationID),
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        querySubscription.notificationInfo = notificationInfo

        _ = try await publicDatabase.merchantAlertsSaveSubscription(querySubscription)
    }

    private func deleteCloudKitSubscription(for subscription: CitySubscription) async throws {
        _ = try await publicDatabase.merchantAlertsDeleteSubscription(withID: cloudKitSubscriptionID(for: subscription.locationID))
    }

    private func fetchDigest(recordID: CKRecord.ID) async throws -> CityDigest {
        let record = try await publicDatabase.merchantAlertsRecord(for: recordID)
        return try CityDigest(record: record)
    }

    private func fetchLatestDigest(for subscription: CitySubscription) async throws -> CityDigest? {
        let predicate = NSPredicate(format: "locationID == %@", subscription.locationID)
        let query = CKQuery(recordType: digestRecordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: "digestWindowEnd", ascending: false)
        ]

        let records = try await publicDatabase.merchantAlertsRecords(
            matching: query,
            resultsLimit: digestCatchUpLimit
        )

        guard let record = records.first,
              MerchantAlertsCatchUpPolicy.isEligible(
                recordCreationDate: record.creationDate,
                digestWindowEnd: record["digestWindowEnd"] as? Date,
                subscriptionCreatedAt: subscription.createdAt
              ) else {
            return nil
        }

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

    private func catchUpMissedDigestIfNeeded() async {
        guard isCloudKitAvailable else { return }
        guard notificationsAuthorized else { return }
        guard let subscription = currentSubscription else { return }

        do {
            guard let digest = try await fetchLatestDigest(for: subscription) else { return }
            guard digest.id != lastDigest?.id else { return }

            lastDigest = digest
            persistLastDigest()

            if UIApplication.shared.applicationState == .active {
                activeDigest = digest
            }

            try await scheduleLocalNotification(for: digest)
        } catch {
            Debug.log("Merchant alerts: digest catch-up failed for \(subscription.locationID): \(error.localizedDescription)")
        }
    }

    private func notificationTitle(for digest: CityDigest) -> String {
        let city = digest.cityDisplayName.components(separatedBy: ",").first ?? digest.cityDisplayName
        if digest.merchantCount == 1 {
            return String(format: NSLocalizedString("New merchant in %@", comment: "Notification title for one new merchant in a city"), city)
        }
        return String(format: NSLocalizedString("New merchants in %@", comment: "Notification title for multiple new merchants in a city"), city)
    }

    private func notificationBody(for digest: CityDigest) -> String {
        let names = Array(digest.topMerchantNames.prefix(2))

        switch names.count {
        case 2 where digest.merchantCount > 2:
            return String(format: NSLocalizedString("%@, %@, and %lld more now accept bitcoin.", comment: "Notification body for two named merchants and additional merchants"), names[0], names[1], digest.merchantCount - 2)
        case 2:
            return String(format: NSLocalizedString("%@ and %@ now accept bitcoin.", comment: "Notification body for two named merchants"), names[0], names[1])
        case 1 where digest.merchantCount > 1:
            return String(format: NSLocalizedString("%@ and %lld more now accept bitcoin.", comment: "Notification body for one named merchant and additional merchants"), names[0], digest.merchantCount - 1)
        case 1:
            return String(format: NSLocalizedString("%@ now accepts bitcoin.", comment: "Notification body for one named merchant"), names[0])
        default:
            return String(format: NSLocalizedString("%lld new merchants now accept bitcoin.", comment: "Notification body when only the merchant count is known"), digest.merchantCount)
        }
    }

    private func cloudKitSubscriptionID(for locationID: String) -> String {
        let digest = SHA256.hash(data: Data(locationID.utf8))
        let hashed = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "city-digest-\(hashed)"
    }

    private func restoreSubscriptionsFromCloudKitIfNeeded() async {
        do {
            let allSubscriptions = try await publicDatabase.merchantAlertsFetchAllSubscriptions()
            let querySubscriptions = allSubscriptions.compactMap { $0 as? CKQuerySubscription }

            guard let querySubscription = querySubscriptions.first(where: { $0.recordType == digestRecordType }),
                  let locationID = extractLocationID(from: querySubscription) else {
                return
            }

            let restored = if let matchedCity = await CityIndexStore.shared.result(forLocationID: locationID) {
                CitySubscription(
                    locationID: matchedCity.locationID,
                    cityKey: matchedCity.cityKey,
                    city: matchedCity.city,
                    region: matchedCity.region,
                    country: matchedCity.country,
                    displayName: matchedCity.displayName
                )
            } else {
                CitySubscription(
                    locationID: locationID,
                    cityKey: locationID,
                    city: "",
                    region: "",
                    country: "",
                    displayName: locationID
                )
            }

            subscriptions = [restored]
            persistSubscriptions()
        } catch {
            Debug.log("Merchant alert CloudKit subscription restore failed: \(error.localizedDescription)")
        }
    }

    private func extractLocationID(from subscription: CKQuerySubscription) -> String? {
        let format = subscription.predicate.predicateFormat
        let matches = format.matches(of: /"([^"]+)"/)
        guard let last = matches.last else { return nil }
        return String(last.1)
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

    private func registerForRemoteNotificationsIfNeeded() {
        guard notificationsAuthorized else { return }
        guard !hasRegisteredForRemoteNotifications else { return }
        guard !isRegisteringForRemoteNotifications else { return }
        isRegisteringForRemoteNotifications = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    func markRemoteNotificationRegistrationSucceeded() {
        isRegisteringForRemoteNotifications = false
        hasRegisteredForRemoteNotifications = true
    }

    func markRemoteNotificationRegistrationFailed() {
        isRegisteringForRemoteNotifications = false
        hasRegisteredForRemoteNotifications = false
    }
}

enum MerchantAlertsCatchUpPolicy {
    static func isEligible(
        recordCreationDate: Date?,
        digestWindowEnd: Date?,
        subscriptionCreatedAt: Date
    ) -> Bool {
        if let recordCreationDate {
            return recordCreationDate >= subscriptionCreatedAt
        }

        guard let digestWindowEnd else {
            return false
        }

        return digestWindowEnd >= subscriptionCreatedAt
    }
}

extension CityDigest {
    init(record: CKRecord) throws {
        guard let cityKey = record["cityKey"] as? String else {
            throw MerchantAlertsError.invalidDigestRecord
        }

        self.id = record.recordID.recordName
        self.locationID = record["locationID"] as? String
        self.cityKey = cityKey
        self.cityDisplayName = (record["cityDisplayName"] as? String) ?? cityKey
        self.digestWindowStart = record["digestWindowStart"] as? Date
        self.digestWindowEnd = record["digestWindowEnd"] as? Date
        self.merchantCount = Int((record["merchantCount"] as? Int64) ?? 0)
        self.merchantIDs = (record["merchantIDs"] as? [String]) ?? []
        self.topMerchantNames = (record["topMerchantNames"] as? [String]) ?? []
        self.timeZoneID = record["timeZoneID"] as? String
        self.deliveryLocalDate = record["deliveryLocalDate"] as? String
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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken _: Data) {
        Task { @MainActor in
            MerchantAlertsManager.shared.markRemoteNotificationRegistrationSucceeded()
        }
        Debug.log("Registered for remote notifications.")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            MerchantAlertsManager.shared.markRemoteNotificationRegistrationFailed()
        }
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

    func merchantAlertsRecords(matching query: CKQuery, resultsLimit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = resultsLimit

            var records: [CKRecord] = []
            var operationError: Error?

            operation.recordMatchedBlock = { _, result in
                switch result {
                case let .success(record):
                    records.append(record)
                case let .failure(error):
                    operationError = error
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    if let operationError {
                        continuation.resume(throwing: operationError)
                    } else {
                        continuation.resume(returning: records)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            add(operation)
        }
    }
}
