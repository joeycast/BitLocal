//
//  Debug.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 6/1/25.
//


import Foundation

struct Debug {
    #if DEBUG
    static let isEnabled = true
    static let isMapLoggingEnabled = ProcessInfo.processInfo.environment["BITLOCAL_MAP_LOGS"] == "1"
    #else
    static let isEnabled = false
    static let isMapLoggingEnabled = false
    #endif

    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let filename = (file as NSString).lastPathComponent
        print("🔍 [\(filename):\(line)] \(function): \(message)")
    }

    static func logAPI(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let filename = (file as NSString).lastPathComponent
        print("🌐 API [\(filename):\(line)] \(function): \(message)")
    }

    static func logCache(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let filename = (file as NSString).lastPathComponent
        print("💾 CACHE [\(filename):\(line)] \(function): \(message)")
    }

    static func logMap(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled, isMapLoggingEnabled else { return }
        let filename = (file as NSString).lastPathComponent
        print("🗺️ MAP [\(filename):\(line)] \(function): \(message)")
    }
}
