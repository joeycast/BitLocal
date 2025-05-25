import SwiftUI
import CoreLocation
import MapKit

// MARK: - NilOnFail property wrapper
@propertyWrapper public struct NilOnFail<T: Codable>: Codable {
    public let wrappedValue: T?
    public init(from decoder: Decoder) throws {
        wrappedValue = try? T(from: decoder)
    }
    public init(_ wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: - APIManager

class APIManager {
    static let shared = APIManager()
    
    let cacheKey = "cachedElements"
    let lastUpdateKey = "lastUpdate"
    
    init() {
        UserDefaults.standard.register(defaults: [lastUpdateKey: "2000-01-01T00:00:00.000Z"])
    }
    
    func fetchElements(in region: MKCoordinateRegion, completion: @escaping ([Element]?) -> Void) {
        let minLatitude = region.center.latitude - (region.span.latitudeDelta / 2)
        let maxLatitude = region.center.latitude + (region.span.latitudeDelta / 2)
        let minLongitude = region.center.longitude - (region.span.longitudeDelta / 2)
        let maxLongitude = region.center.longitude + (region.span.longitudeDelta / 2)
        
        let urlString = "https://api.btcmap.org/v2/elements?bbox=\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL string: \(urlString)")
            completion(nil)
            return
        }
        
        // Log the requesting URL
        print("Requesting URL: \(url.absoluteString)")
        LogManager.shared.log("Requesting URL: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
            guard let self = self else {
                completion(nil)
                return
            }
            
            guard let data = data, error == nil else {
                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                LogManager.shared.log("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let fetchedElements = try decoder.decode([Element].self, from: data)
                
                // Update cache if needed
                self.updateCacheWithFetchedElements(fetchedElements: fetchedElements)
                
                completion(fetchedElements)
            } catch {
                print("JSON Decoding Error: \(error)")
                LogManager.shared.log("JSON Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    private func updateCacheWithFetchedElements(fetchedElements: [Element]) {
        let cacheKey = self.cacheKey
        var cachedElements = UserDefaults.standard.getElements(forKey: cacheKey) ?? []
        var elementsDictionary = Dictionary(uniqueKeysWithValues: cachedElements.map { ($0.id, $0) })
        fetchedElements.forEach { element in
            elementsDictionary[element.id] = element
        }
        cachedElements = Array(elementsDictionary.values)
        UserDefaults.standard.setElements(cachedElements, forKey: cacheKey)
    }
    
    func getElements(completion: @escaping ([Element]?) -> Void) {
        let lastUpdate = UserDefaults.standard.string(forKey: lastUpdateKey) ?? ""
        let urlString = "https://api.btcmap.org/v2/elements?updated_since=\(lastUpdate)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL string: \(urlString)")
            LogManager.shared.log("Invalid URL string: \(urlString)")
            completion(nil)
            return
        }
        
        // Log the requesting URL
        print("Requesting URL: \(url.absoluteString)")
        LogManager.shared.log("Requesting URL: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
            guard let data = data, error == nil else {
                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                LogManager.shared.log("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
                print("Content-Type: \(contentType ?? "Unknown")")
                LogManager.shared.log("Content-Type: \(contentType ?? "Unknown")")
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
                LogManager.shared.log("HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            let responsePreview = String(data: data, encoding: .utf8) ?? ""
            print("API response preview: \(responsePreview.prefix(1000))")
            
            do {
                let decoder = JSONDecoder()
                decoder.dataDecodingStrategy = .base64
                
                let fetchedElements = try decoder.decode([Element].self, from: data)
                print("Decoded JSON: \(String(data: data, encoding: .utf8) ?? "")")
                print("Decoded Elements: \(fetchedElements)")
                self?.updateCacheWithFetchedElements(fetchedElements: fetchedElements)
                
                if let mostRecentUpdate = fetchedElements.max(by: { $0.updatedAt ?? "" < $1.updatedAt ?? "" })?.updatedAt {
                    print("Updating lastUpdateKey to: \(mostRecentUpdate)")
                    LogManager.shared.log("Updating lastUpdateKey to: \(mostRecentUpdate)")
                    UserDefaults.standard.setValue(mostRecentUpdate, forKey: self?.lastUpdateKey ?? "")
                    let updatedTime = UserDefaults.standard.string(forKey: self?.lastUpdateKey ?? "")
                    print("Verified lastUpdateKey is now: \(String(describing: updatedTime))")
                    LogManager.shared.log("Verified lastUpdateKey is now: \(String(describing: updatedTime))")
                }
                
                let updatedCache = UserDefaults.standard.getElements(forKey: self?.cacheKey ?? "")
                completion(updatedCache)
            } catch {
                let responsePreview = String(data: data, encoding: .utf8) ?? "<Could not decode as UTF-8>"
                print("RAW API response preview on decoding error: \(responsePreview.prefix(2000))")
                print("JSON Decoding Error: \(error)")
                LogManager.shared.log("JSON Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - LogManager

class LogManager {
    static let shared = LogManager()
    private init() {}
    private(set) var logs: [String] = []
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        logs.append(logMessage)
    }
    
    func allLogs() -> String {
        return logs.joined(separator: "\n")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}
