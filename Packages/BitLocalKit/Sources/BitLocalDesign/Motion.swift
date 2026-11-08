import SwiftUI

/// Named motion tokens (docs/redesign/ui-redesign.md section 5).
/// Frequency decides motion: typing and keyboard navigation never animate;
/// system responses use a strong ease-out; anything a finger can interrupt is a spring.
public enum Motion {
    /// Button press-down feedback.
    public static let press = Animation.spring(duration: 0.16, bounce: 0)
    /// The system responding (ease-out, fast first frame).
    public static let respond = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20)
    /// On-screen movement.
    public static let move = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.28)
    /// Pin select, card paging.
    public static let select = Animation.spring(duration: 0.30, bounce: 0.15)
    /// Following a drag.
    public static let gesture = Animation.interactiveSpring(duration: 0.30, extraBounce: 0)
    /// Rare moments only (alerts enabled, business submitted).
    public static let delight = Animation.spring(duration: 0.50, bounce: 0.25)
    /// Map controls fading as the sheet passes the card detent.
    public static let fade = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
    /// Exits are faster than entrances.
    public static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)

    /// `animation` unless Reduce Motion is on, in which case nil (an instant change).
    public static func unlessReduced(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Scale-on-press for custom buttons (0.97 with `Motion.press`, release with `Motion.respond`).
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.respond, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    public static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
