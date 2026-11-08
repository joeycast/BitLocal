import Foundation
import BitLocalDomain

/// The rules for swiping the merchant card between places (ui-redesign.md 4.5 and 5).
public enum CardPaging {
    /// Travel before the card claims a drag, so vertical sheet drags are never stolen.
    public static let claimDistance: Double = 10
    /// A flick faster than 0.11 pt/ms pages even below the distance threshold.
    public static let flickVelocity: Double = 110
    /// Share of the card width a slow drag must cover to page.
    public static let distanceThreshold: Double = 0.25
    /// Resistance past the first or last merchant.
    public static let rubberBandFactor: Double = 0.3

    /// True once a drag is far enough and mostly horizontal.
    public static func claims(dx: Double, dy: Double) -> Bool {
        abs(dx) >= claimDistance && abs(dx) > abs(dy) * 1.5
    }

    /// +1 for the next merchant (drag left), -1 for the previous one, 0 to stay.
    /// `velocity` is in points per second, along x.
    public static func step(translation: Double, velocity: Double, width: Double) -> Int {
        let threshold = max(width, 1) * distanceThreshold
        if translation <= -threshold || velocity <= -flickVelocity { return 1 }
        if translation >= threshold || velocity >= flickVelocity { return -1 }
        return 0
    }

    /// The merchant `step` places away from `current` in `order`, or nil at either end.
    public static func neighbor<ID: Equatable>(of current: ID, in order: [ID], step: Int) -> ID? {
        guard step != 0, let index = order.firstIndex(of: current) else { return nil }
        let target = index + step
        return order.indices.contains(target) ? order[target] : nil
    }

    /// The card offset to draw for a drag: free when there is a neighbor that way, damped when there isn't.
    public static func offset(for translation: Double, hasPrevious: Bool, hasNext: Bool) -> Double {
        if translation < 0 && !hasNext { return translation * rubberBandFactor }
        if translation > 0 && !hasPrevious { return translation * rubberBandFactor }
        return translation
    }
}
