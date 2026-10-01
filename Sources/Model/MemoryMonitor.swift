import Combine
import Darwin
import Foundation

/// Samples the Mac's own memory pressure and offers it as a provider-style
/// snapshot, so the notch can draw the machine's RAM on the very same ring the
/// AI providers use — no new geometry, hover or tooltip code, only one more
/// cell in the strip.
///
/// The fraction is "memory in use" the way Activity Monitor's graph means it:
/// the pages actively held — app/anonymous, wired down, and whatever the
/// compressor is sitting on — over the physical total. The inactive, cached and
/// purgeable pages the kernel can hand back the instant something asks are left
/// out on purpose: counting them as spent would peg the ring near full on a
/// perfectly healthy Mac and mean nothing.
@MainActor
final class MemoryMonitor: ObservableObject {
    /// Nil while the monitor is switched off, or before the first sample. The
    /// app appends it to the notch strip when it is present.
    @Published private(set) var snapshot: ProviderSnapshot?

    private var timer: Timer?
    private let interval: TimeInterval

    /// `nonisolated` so the app can hold it as a stored-property default
    /// (`private let memoryMonitor = MemoryMonitor()`) from `AppDelegate`'s own
    /// init, which is not main-actor-isolated. Safe because it only stores the
    /// interval — it touches no isolated state. Everything that does runs
    /// through `setEnabled`/`sample`, which stay on the main actor.
    nonisolated init(interval: TimeInterval = 4) {
        self.interval = interval
    }

    /// Driven from the `showMemoryMonitor` preference. Off means no timer and no
    /// snapshot, so a Mac whose owner does not want it pays nothing — the reading
    /// is a syscall, but a fanless dual-core has no cycles to waste on one every
    /// few seconds for a ring nobody asked for.
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
        guard let reading = Self.read() else { return }
        snapshot = Self.makeSnapshot(from: reading)
    }

    /// A single reading of physical memory use.
    struct Reading: Equatable {
        let usedBytes: UInt64
        let totalBytes: UInt64

        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
        }
    }

    /// Reads the kernel's virtual-memory counters. Returns nil only if the Mach
    /// call fails, which it does not in practice — the ring simply keeps its last
    /// reading rather than flashing empty on a hiccup.
    static func read() -> Reading? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = (active + wired + compressed) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        return Reading(usedBytes: used, totalBytes: total)
    }

    /// Wraps a reading as a `ProviderSnapshot` of the new `.system` kind: one
    /// window carrying the used fraction so the ring fills and colours by band,
    /// the GB figures on the row for the hover card, and a stable id so the cell
    /// keeps its place in the strip across samples.
    static func makeSnapshot(from reading: Reading) -> ProviderSnapshot {
        let window = LimitWindow(
            id: "ram",
            label: gigabytesText(used: reading.usedBytes, total: reading.totalBytes),
            usedFraction: reading.usedFraction
        )
        return ProviderSnapshot(
            id: "system.memory",
            displayName: L10n.t("Memory"),
            glyph: .memory,
            fidelity: .official,
            status: .ok,
            windows: [window],
            headlineID: "ram",
            kind: .system
        )
    }

    /// "5.3 / 8.0 GB" — used over total, in the binary gigabytes Activity Monitor
    /// and the About This Mac panel both use, so the number matches what the
    /// owner sees elsewhere.
    static func gigabytesText(used: UInt64, total: UInt64) -> String {
        let gb = 1_073_741_824.0
        return String(format: "%.1f / %.1f GB", Double(used) / gb, Double(total) / gb)
    }
}
