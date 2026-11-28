//
//  DistanceUnit.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case auto
    case miles
    case kilometers

    var id: String { self.rawValue }
    var label: String {
        switch self {
        case .auto: return String(localized: "Auto", comment: "Automatic distance unit option")
        case .miles: return String(localized: "Miles", comment: "Miles distance unit option")
        case .kilometers: return String(localized: "Kilometers", comment: "Kilometers distance unit option")
        }
    }
}