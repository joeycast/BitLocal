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
        case .auto: return "Auto"
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }
}