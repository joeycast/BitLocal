//import SwiftUI
//
//class LogManager {
//    static let shared = LogManager()
//    private init() {} // Private constructor
//    
//    private(set) var logs: [String] = []
//    
//    func log(_ message: String) {
//        // Here you can also include timestamps or other metadata
//        logs.append(message)
//    }
//    
//    func allLogs() -> String {
//        return logs.joined(separator: "\n")
//    }
//    
//    func clearLogs() {
//        logs.removeAll()
//    }
//}
