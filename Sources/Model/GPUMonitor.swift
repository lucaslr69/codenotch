import Combine
import Foundation
import IOKit

/// Samples the Mac's own GPU load and offers it as a provider-style snapshot,
/// the same way `MemoryMonitor` and `CPUMonitor` do — one more cell in the
/// strip, no new geometry.
///
/// There is no public API for this. The figure comes from the IO registry: the
/// `IOAccelerator` service publishes a `PerformanceStatistics` dictionary that
/// carries the driver's own busy percentage, readable from user space with no
/// entitlement and no root. `powermetrics` would be the documented route and it
/// needs root, which a menu-bar app cannot have.
///
/// Because it is the driver's dictionary rather than a contract, the key names
/// differ by GPU family and the cell is built to disappear rather than guess:
/// `read` returns nil when nothing recognisable is published, and the app
/// appends no cell at all. A missing ring is honest; a ring pinned at zero on
/// hardware we cannot read would be a lie.
@MainActor
final class GPUMonitor: ObservableObject {
    /// Nil while the monitor is switched off, before the first sample, or on
    /// hardware whose driver publishes none of the keys below.
    @Published private(set) var snapshot: ProviderSnapshot?

    private var timer: Timer?
    private let interval: TimeInterval

    /// `nonisolated` for the same reason as the other two monitors': so
    /// `AppDelegate` can hold it as a stored-property default.
    nonisolated init(interval: TimeInterval = 4) {
        self.interval = interval
    }

    /// Driven from the `showGPUMonitor` preference.
    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            timer?.invalidate()
            timer = nil
            snapshot = nil
            return
        }
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        guard let load = Self.read() else { return }
        snapshot = Self.makeSnapshot(load: load)
    }

    /// The keys a GPU family publishes its busy share under, probed in order.
    ///
    /// `"Device Utilization %"` is the one measured on Apple silicon — an M4
    /// published `25` for 25% — and is also what Intel's integrated driver
    /// uses. `"GPU Core Utilization"` is AMD's. `"Renderer Utilization %"` is
    /// last because on Apple silicon it sits beside the device figure and
    /// reports only the render pipeline's share, which is a narrower number
    /// than the one the cell means.
    nonisolated static let utilizationKeys = [
        "Device Utilization %",
        "GPU Core Utilization",
        "Renderer Utilization %",
    ]

    /// The busiest accelerator's load, or nil when none publishes a figure we
    /// recognise.
    ///
    /// Busiest rather than first: a dual-GPU Intel Mac exposes both the
    /// integrated and the discrete accelerator, and the idle one would mask the
    /// working one. Whichever is doing the work is the one the owner means.
    nonisolated static func read() -> Double? {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("IOAccelerator")
        // `IOServiceGetMatchingServices` consumes the matching dictionary, so
        // there is nothing to release here on either path.
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var busiest: Double?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let statistics = performanceStatistics(of: service),
                  let load = utilization(in: statistics) else { continue }
            busiest = max(busiest ?? 0, load)
        }
        return busiest
    }

    nonisolated private static func performanceStatistics(of service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() else { return nil }
        return (properties as NSDictionary)["PerformanceStatistics"] as? [String: Any]
    }

    /// The first recognisable figure in a driver's statistics dictionary,
    /// normalised to 0...1.
    nonisolated static func utilization(in statistics: [String: Any]) -> Double? {
        for key in utilizationKeys {
            guard let raw = (statistics[key] as? NSNumber)?.doubleValue else { continue }
            if let load = fraction(fromRaw: raw) { return load }
        }
        return nil
    }

    /// Normalises a driver's raw figure into 0...1.
    ///
    /// Apple silicon and Intel publish a plain percent, measured: `25` meant
    /// 25%. AMD's `"GPU Core Utilization"` is reported on a far larger scale on
    /// the drivers that publish it, so a figure above 100 is divided down
    /// rather than clamped to a ring that would sit permanently full.
    ///
    /// That divisor is the one number here nobody has read through real AMD
    /// hardware — it is unverified, and deliberately fails closed: a figure
    /// that still makes no sense as a percentage after scaling returns nil,
    /// which drops the cell instead of drawing something we cannot stand
    /// behind. If an AMD Mac shows no GPU ring, this function is the single
    /// place to correct.
    nonisolated static func fraction(fromRaw raw: Double) -> Double? {
        guard raw.isFinite, raw >= 0 else { return nil }
        if raw <= 100 { return raw / 100 }
        // A percent that overshot its own ceiling, which drivers do in passing.
        // Nothing on the larger scale lands in 100...200 — it is ten million
        // times coarser, so an idle AMD GPU reads 0 and a busy one reads in the
        // hundreds of millions. There is no realistic collision in this band.
        if raw <= 200 { return 1 }
        let percent = raw / 10_000_000
        guard percent <= 200 else { return nil }
        return min(percent / 100, 1)
    }

    /// Wraps a load as a `ProviderSnapshot` of the `.system` kind, the same
    /// shape `MemoryMonitor` and `CPUMonitor` produce.
    nonisolated static func makeSnapshot(load: Double) -> ProviderSnapshot {
        let window = LimitWindow(
            id: "load",
            label: CPUMonitor.percentText(load),
            usedFraction: load
        )
        return ProviderSnapshot(
            id: "system.gpu",
            displayName: L10n.t("GPU"),
            glyph: .gpu,
            fidelity: .official,
            status: .ok,
            windows: [window],
            headlineID: "load",
            kind: .system
        )
    }
}
