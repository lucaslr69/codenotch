import SwiftUI

// macOS 13 (Ventura) back-deployment shims. The app's rendering is already
// 13-safe and nothing here uses a macOS 15 API; these are the only SwiftUI
// call sites that need a floor above 13. Each is gated with a graceful
// fallback rather than dropping the feature, so the app still builds and runs
// on Ventura while keeping the full animation on 14+. Delete this file and
// inline the modifiers again if the deployment target ever rises back to 14+.
extension View {
    /// `scrollBounceBehavior(.basedOnSize)` (macOS 14) stops a short scroll
    /// view from bouncing when its content already fits. On 13 the default
    /// bounce is harmless, so the view is returned unchanged.
    @ViewBuilder
    func scrollBounceBasedOnSize() -> some View {
        if #available(macOS 14.0, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    /// A one-shot spring "pop" — scale up past 1, then settle back — when
    /// `trigger` changes. A keyframed spring on macOS 14+, no animation on 13.
    @ViewBuilder
    func bouncePop(trigger: some Equatable, peak: CGFloat) -> some View {
        if #available(macOS 14.0, *) {
            keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(peak, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
        } else {
            self
        }
    }

    /// A press squeeze — dip below 1, then settle back — keyed off a click
    /// counter. Keyframed on macOS 14+, no animation on 13.
    @ViewBuilder
    func pressSqueeze(trigger: some Equatable, squeeze: CGFloat) -> some View {
        if #available(macOS 14.0, *) {
            keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { orb, scale in
                orb.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(squeeze, duration: 0.09, spring: .snappy)
                SpringKeyframe(1, duration: 0.34, spring: .bouncy)
            }
        } else {
            self
        }
    }

    /// `.symbolEffect(.bounce, value:)` (macOS 14) bounces an SF Symbol when
    /// `value` changes. A no-op on 13.
    @ViewBuilder
    func bounceSymbol(value: some Equatable) -> some View {
        if #available(macOS 14.0, *) {
            symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}
