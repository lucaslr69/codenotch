import Combine
import Darwin
import Foundation

/// Samples the Mac's own processor load and offers it as a provider-style
/// snapshot, so the notch can draw the machine's CPU on the very same ring the
/// AI providers use — no new geometry, hover or tooltip code, only one more
/// cell in the strip. The shape deliberately mirrors `MemoryMonitor`.
///
/// The fraction is the busy share of the ticks that elapsed between two
/// samples: user, system and nice time over everything including idle, summed
/// across cores. That makes it a *rate* rather than a level, which is why this
/// monitor keeps state where `MemoryMonitor` does not — the kernel only offers
/// counters that climb since boot, and a single reading of those says what the
/// Mac has done all week, not what it is doing now.
@MainActor
final class CPUMonitor: ObservableObject {
    /// Nil while the monitor is switched off, and for the first sample after it
    /// is switched on — one reading cannot make a rate. The app appends it to
    /// the notch strip when it is present.
    @Published private(set) var snapshot: ProviderSnapshot?

    private var timer: Timer?
    private let interval: TimeInterval
    private var previous: Ticks?

    /// `nonisolated` for the same reason as `MemoryMonitor`'s: so the app can
    /// hold it as a stored-property default from `AppDelegate`'s own init,
    /// which is not main-actor-isolated. Safe because it only stores the
    /// interval.
    nonisolated init(interval: TimeInterval = 4) {
        self.interval = interval
    }

    /// Driven from the `showCPUMonitor` preference. Off means no timer, no
    /// snapshot and no remembered ticks, so switching it back on measures a
    /// fresh interval rather than averaging over the time it spent dark.
    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            timer?.invalidate()
            timer = nil
            snapshot = nil
            previous = nil
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
        guard let ticks = Self.read() else { return }
        defer { previous = ticks }
        guard let previous, let load = Self.load(from: previous, to: ticks) else { return }
        snapshot = Self.makeSnapshot(load: load)
    }

    /// Cumulative CPU ticks since boot, summed over every core.
    struct Ticks: Equatable {
        let busy: UInt64
        let idle: UInt64

        var total: UInt64 { busy &+ idle }
    }

    /// Reads the kernel's per-core tick counters. Returns nil only if the Mach
    /// call fails, which it does not in practice — the ring keeps its last
    /// reading rather than flashing empty on a hiccup.
    nonisolated static func read() -> Ticks? {
        var cores = natural_t(0)
        var info: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: UnsafeRawPointer(info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var busy: UInt64 = 0
        var idle: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(cores) {
            let base = core * states
            busy &+= tick(info[base + Int(CPU_STATE_USER)])
            busy &+= tick(info[base + Int(CPU_STATE_SYSTEM)])
            busy &+= tick(info[base + Int(CPU_STATE_NICE)])
            idle &+= tick(info[base + Int(CPU_STATE_IDLE)])
        }
        return Ticks(busy: busy, idle: idle)
    }

    /// Reinterprets a counter's bits as unsigned rather than converting it.
    ///
    /// `integer_t` is signed 32-bit and these counters only climb: at the
    /// kernel's 100Hz a single core passes `Int32.max` after about 248 days of
    /// uptime and the value the kernel hands back goes negative. `UInt64(_:)`
    /// on a negative number traps, so an uptime nobody tests for would crash
    /// the app. The counter is unsigned as far as the kernel is concerned, so
    /// reading the bits that way is both crash-free and the right number.
    nonisolated private static func tick(_ raw: integer_t) -> UInt64 {
        UInt64(UInt32(bitPattern: raw))
    }

    /// The busy share of the ticks that elapsed between two readings, or nil
    /// when no time passed — two samples inside the same tick say nothing, and
    /// dividing by their difference would be a divide by zero.
    ///
    /// Counters that went backwards are treated as no time passed rather than
    /// wrapped: that happens when a core is taken offline between samples, and
    /// the honest answer is to skip the interval instead of inventing a spike.
    nonisolated static func load(from previous: Ticks, to current: Ticks) -> Double? {
        guard current.total > previous.total, current.busy >= previous.busy else { return nil }
        let elapsed = current.total - previous.total
        let busy = current.busy - previous.busy
        guard busy <= elapsed else { return nil }
        return min(max(Double(busy) / Double(elapsed), 0), 1)
    }

    /// Wraps a load as a `ProviderSnapshot` of the `.system` kind: one window
    /// carrying the busy fraction so the ring fills and colours by band, and a
    /// stable id so the cell keeps its place in the strip across samples.
    nonisolated static func makeSnapshot(load: Double) -> ProviderSnapshot {
        let window = LimitWindow(
            id: "load",
            label: percentText(load),
            usedFraction: load
        )
        return ProviderSnapshot(
            id: "system.cpu",
            displayName: L10n.t("CPU"),
            glyph: .cpu,
            fidelity: .official,
            status: .ok,
            windows: [window],
            headlineID: "load",
            kind: .system
        )
    }

    /// "47%" — whole percent, the way Activity Monitor's own CPU readout rounds
    /// it, so the number matches what the owner sees elsewhere.
    nonisolated static func percentText(_ load: Double) -> String {
        String(format: "%.0f%%", load * 100)
    }
}
