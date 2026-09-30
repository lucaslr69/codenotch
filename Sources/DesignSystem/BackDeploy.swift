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

    /// `.pointerStyle(.grabIdle)` (macOS 15) shows the open-hand cursor on
    /// hover. On 13/14 the cursor rect + `GrabCursor` overlay beside this call
    /// already covers the cursor, so dropping the modifier loses nothing.
    @ViewBuilder
    func grabPointerStyle(_ active: Bool) -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(active ? .grabIdle : nil)
        } else {
            self
        }
    }
}

extension Path {
    /// `union(_:eoFill:)` (macOS 14) merges two paths into one outline. On 13
    /// the paths are appended instead: filled or clipped with the default
    /// non-zero winding — which is how this shape is always used — the two
    /// overlapping pieces paint the same region a true union would. The seam a
    /// union removes only reappears when the combined path is *stroked*, which
    /// this one never is.
    func unioned(with other: Path) -> Path {
        if #available(macOS 14.0, *) {
            return union(other)
        } else {
            var merged = self
            merged.addPath(other)
            return merged
        }
    }
}
