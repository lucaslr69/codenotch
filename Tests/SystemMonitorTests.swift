import AppKit
import XCTest
@testable import Codenotch

/// Covers the arithmetic the CPU and GPU cells rest on, which is the part that
/// can be checked without the hardware underneath: tick deltas and the
/// normalising of whatever figure a graphics driver happened to publish.
final class SystemMonitorTests: XCTestCase {

    // MARK: - CPU

    func testLoadIsTheBusyShareOfElapsedTicks() throws {
        let before = CPUMonitor.Ticks(busy: 1_000, idle: 9_000)
        let after = CPUMonitor.Ticks(busy: 1_025, idle: 9_075)
        let load = try XCTUnwrap(CPUMonitor.load(from: before, to: after))
        XCTAssertEqual(load, 0.25, accuracy: 0.0001)
    }

    func testLoadIsNilWhenNoTicksElapsed() {
        let ticks = CPUMonitor.Ticks(busy: 1_000, idle: 9_000)
        XCTAssertNil(CPUMonitor.load(from: ticks, to: ticks))
    }

    /// A core taken offline between samples makes the counters fall. Skipping
    /// the interval is the honest answer; wrapping would draw a spike that
    /// never happened.
    func testLoadIsNilWhenCountersWentBackwards() {
        let before = CPUMonitor.Ticks(busy: 5_000, idle: 5_000)
        let after = CPUMonitor.Ticks(busy: 4_000, idle: 4_000)
        XCTAssertNil(CPUMonitor.load(from: before, to: after))
    }

    /// Busy time cannot outrun the interval it was spent in. When it appears
    /// to, the counters are not comparable — idle fell while busy climbed — and
    /// the share would come out above one.
    func testLoadIsNilWhenBusyGrewMoreThanTheInterval() {
        let before = CPUMonitor.Ticks(busy: 0, idle: 100)
        let after = CPUMonitor.Ticks(busy: 200, idle: 0)
        XCTAssertNil(CPUMonitor.load(from: before, to: after))
    }

    func testFullyBusyAndFullyIdleReachTheEnds() throws {
        let start = CPUMonitor.Ticks(busy: 10, idle: 10)

        let busy = CPUMonitor.Ticks(busy: 110, idle: 10)
        XCTAssertEqual(try XCTUnwrap(CPUMonitor.load(from: start, to: busy)), 1)

        let idle = CPUMonitor.Ticks(busy: 10, idle: 110)
        XCTAssertEqual(try XCTUnwrap(CPUMonitor.load(from: start, to: idle)), 0)
    }

    func testCPUSnapshotIsASystemCellWithTheLoadOnItsHeadlineWindow() throws {
        let snapshot = CPUMonitor.makeSnapshot(load: 0.42)
        XCTAssertEqual(snapshot.id, "system.cpu")
        XCTAssertEqual(snapshot.kind, .system)
        XCTAssertEqual(snapshot.glyph, .cpu)
        XCTAssertEqual(snapshot.headlineID, "load")

        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.id, snapshot.headlineID)
        XCTAssertEqual(try XCTUnwrap(window.usedFraction), 0.42, accuracy: 0.0001)
        XCTAssertEqual(window.label, "42%")
    }

    func testPercentTextRoundsToWholePercent() {
        XCTAssertEqual(CPUMonitor.percentText(0), "0%")
        XCTAssertEqual(CPUMonitor.percentText(0.256), "26%")
        XCTAssertEqual(CPUMonitor.percentText(1), "100%")
    }

    /// The reading itself. It cannot assert a figure — the load is whatever the
    /// machine is doing — but it can assert that the Mach call answers and that
    /// two readings are usable together, which is what the monitor needs.
    func testReadReturnsClimbingCounters() throws {
        let first = try XCTUnwrap(CPUMonitor.read())
        XCTAssertGreaterThan(first.total, 0)

        let second = try XCTUnwrap(CPUMonitor.read())
        XCTAssertGreaterThanOrEqual(second.total, first.total)
        XCTAssertGreaterThanOrEqual(second.busy, first.busy)
    }

    // MARK: - GPU

    /// Apple silicon and Intel publish a plain percent. Measured on an M4:
    /// `"Device Utilization %"` was 25 while the GPU was a quarter busy.
    func testPlainPercentBecomesAFraction() throws {
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 0)), 0)
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 25)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 100)), 1)
    }

    func testPercentOvershootClampsRatherThanFallingThroughToTheLargeScale() throws {
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 101)), 1)
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 200)), 1)
    }

    /// AMD's larger scale. Unverified against real AMD hardware — see
    /// `GPUMonitor.fraction`. The test pins the arithmetic so that correcting
    /// the divisor is a one-line change with a failing test to prove it.
    func testLargeScaleIsDividedDown() throws {
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 250_000_000)),
                       0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.fraction(fromRaw: 1_000_000_000)), 1)
    }

    func testUnreadableFiguresAreNilSoTheCellDisappears() {
        XCTAssertNil(GPUMonitor.fraction(fromRaw: -1))
        XCTAssertNil(GPUMonitor.fraction(fromRaw: .nan))
        XCTAssertNil(GPUMonitor.fraction(fromRaw: .infinity))
        XCTAssertNil(GPUMonitor.fraction(fromRaw: 5_000_000_000))
    }

    func testDeviceUtilizationWinsOverTheRendererFigure() throws {
        let statistics: [String: Any] = [
            "Renderer Utilization %": 9,
            "Device Utilization %": 64,
        ]
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.utilization(in: statistics)),
                       0.64, accuracy: 0.0001)
    }

    func testFallsBackThroughTheKeyOrder() throws {
        let amd: [String: Any] = ["GPU Core Utilization": 500_000_000]
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.utilization(in: amd)), 0.5, accuracy: 0.0001)

        let rendererOnly: [String: Any] = ["Renderer Utilization %": 12]
        XCTAssertEqual(try XCTUnwrap(GPUMonitor.utilization(in: rendererOnly)),
                       0.12, accuracy: 0.0001)
    }

    func testUtilizationIsNilWhenNothingRecognisableIsPublished() {
        XCTAssertNil(GPUMonitor.utilization(in: [:]))
        XCTAssertNil(GPUMonitor.utilization(in: ["Alloc system memory": 887_865_344]))
    }

    /// A key that is present but holds something that is not a number at all.
    /// The driver dictionary is not a contract, so this has to be survivable.
    func testNonNumericValuesAreIgnored() {
        XCTAssertNil(GPUMonitor.utilization(in: ["Device Utilization %": "busy"]))
    }

    func testGPUSnapshotIsASystemCell() throws {
        let snapshot = GPUMonitor.makeSnapshot(load: 0.6)
        XCTAssertEqual(snapshot.id, "system.gpu")
        XCTAssertEqual(snapshot.kind, .system)
        XCTAssertEqual(snapshot.glyph, .gpu)
        XCTAssertEqual(snapshot.headlineID, "load")

        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(try XCTUnwrap(window.usedFraction), 0.6, accuracy: 0.0001)
    }

    // MARK: - Glyphs

    /// The system cells are the only ones drawn from SF Symbols, and every name
    /// here has to exist on the oldest macOS the app runs on — `cpu` and
    /// `memorychip` arrived in 2020, `cube.transparent` in 2019, all before
    /// Ventura.
    func testSystemCellsCarryASymbolAndProvidersDoNot() {
        XCTAssertEqual(ProviderGlyph.memory.systemSymbolName, "memorychip")
        XCTAssertEqual(ProviderGlyph.cpu.systemSymbolName, "cpu")
        XCTAssertEqual(ProviderGlyph.gpu.systemSymbolName, "cube.transparent")

        XCTAssertNil(ProviderGlyph.claude.systemSymbolName)
        XCTAssertNil(ProviderGlyph.openai.systemSymbolName)
        XCTAssertNil(ProviderGlyph.ollama.systemSymbolName)
    }

    func testSystemSymbolsResolveOnThisOS() throws {
        for glyph in [ProviderGlyph.memory, .cpu, .gpu] {
            let name = try XCTUnwrap(glyph.systemSymbolName)
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "SF Symbol \(name) does not resolve — the cell would draw blank"
            )
        }
    }

    /// The raw values reach the archive, so a rename would make stored readings
    /// undecodable — the same trap the `gemini` case documents.
    func testNewGlyphRawValuesAreStable() {
        XCTAssertEqual(ProviderGlyph.cpu.rawValue, "cpu")
        XCTAssertEqual(ProviderGlyph.gpu.rawValue, "gpu")
    }
}
