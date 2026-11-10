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
extension DistanceUnit {
    /// Whether this setting shows kilometers and meters.
    var usesMetric: Bool {
        switch self {
        case .auto: Locale.current.measurementSystem == .metric
        case .miles: false
        case .kilometers: true
        }
    }

    /// One distance style everywhere (list rows, the merchant card, VoiceOver):
    /// "450 ft", "0.3 mi", "12 mi" or "350 m", "1.2 km", "12 km". The list used
    /// two decimals ("0.15 mi") while the card used one ("0.2 mi") for the same place.
    func format(meters: Double) -> String {
        let oneDecimal = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        if usesMetric {
            if meters < 1_000 {
                let rounded = max(10, (meters / 10).rounded() * 10)
                return Measurement(value: rounded, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: whole))
            }
            let km = meters / 1_000
            return Measurement(value: km, unit: UnitLength.kilometers)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: km < 10 ? oneDecimal : whole))
        }
        let miles = meters / 1_609.344
        if miles < 0.1 {
            let feet = max(50, (meters * 3.28084 / 50).rounded() * 50)
            return Measurement(value: feet, unit: UnitLength.feet)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: whole))
        }
        return Measurement(value: miles, unit: UnitLength.miles)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: miles < 10 ? oneDecimal : whole))
    }
}
