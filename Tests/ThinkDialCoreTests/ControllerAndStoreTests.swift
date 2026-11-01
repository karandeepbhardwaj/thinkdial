import XCTest
@testable import ThinkDialCore

final class ControllerAndStoreTests: XCTestCase {
    func testRetrySleepsBetweenFailuresThenSucceeds() async {
        let counter = AttemptCounter()
        let sleeps = ValueBox<[UInt64]>([])
        let value = try? await Retry.run(attempts: 4, delayNanoseconds: 25, sleep: { sleeps.value.append($0) }) { () -> Int in
            let attempt = await counter.next()
            if attempt < 3 { throw DDCError.readFailed(0x10) }
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(sleeps.value, [25, 25])
    }

    func testRetryDoesNotSleepAfterTheFinalFailure() async {
        let sleeps = ValueBox(0)
        do {
            _ = try await Retry.run(attempts: 2, delayNanoseconds: 5, sleep: { _ in sleeps.value += 1 }) { () -> Int in
                throw DDCError.writeFailed(0x10)
            }
            XCTFail("expected throw")
        } catch let error as DDCError {
            XCTAssertEqual(error, .writeFailed(0x10))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(sleeps.value, 1)
    }

    func testSliderWritesCollapseToTheLatestValue() async throws {
        let mock = MockDDCBackend.demo()
        let gate = FirstSleepGate()
        let controller = DDCController(
            backend: mock,
            minIntervalNanoseconds: 80_000_000,
            retryAttempts: 1,
            retryDelayNanoseconds: 0,
            sleep: { _ in await gate.sleep() }
        )
        await controller.enqueueWrite(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.brightness, value: 10)
        await controller.enqueueWrite(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.brightness, value: 70)
        await controller.enqueueWrite(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.brightness, value: 33)
        await controller.enqueueWrite(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.contrast, value: 61)
        gate.release()
        await controller.flush()

        let brightness = try await mock.read(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.brightness)
        XCTAssertEqual(brightness.current, 33)
        let contrast = try await mock.read(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.contrast)
        XCTAssertEqual(contrast.current, 61)
        let brightnessWrites = await mock.writes(code: MCCSCatalog.Code.brightness, display: MockDDCBackend.lenovoID)
        XCTAssertEqual(brightnessWrites, [33])
    }

    func testWriteNowRetriesThenRecords() async throws {
        let mock = MockDDCBackend.demo()
        await mock.failNextWrites(2)
        let controller = DDCController(
            backend: mock,
            minIntervalNanoseconds: 0,
            retryAttempts: 3,
            retryDelayNanoseconds: 0,
            sleep: { _ in }
        )
        try await controller.writeNow(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.volume, value: 15)
        let volume = try await mock.read(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.volume)
        let volumeWrites = await mock.writes(code: MCCSCatalog.Code.volume, display: MockDDCBackend.lenovoID)
        XCTAssertEqual(volume.current, 15)
        XCTAssertEqual(volumeWrites, [15])
    }

    func testWriteNowGivesUpAfterTheAttemptBudget() async {
        let mock = MockDDCBackend.demo()
        await mock.failNextWrites(5)
        let controller = DDCController(
            backend: mock,
            minIntervalNanoseconds: 0,
            retryAttempts: 3,
            retryDelayNanoseconds: 0,
            sleep: { _ in }
        )
        do {
            try await controller.writeNow(display: MockDDCBackend.lenovoID, code: 0x10, value: 9)
            XCTFail("expected failure")
        } catch let error as DDCError {
            XCTAssertEqual(error, .writeFailed(0x10))
        } catch {
            XCTFail("unexpected \(error)")
        }
        let brightness = try? await mock.read(display: MockDDCBackend.lenovoID, code: 0x10)
        XCTAssertEqual(brightness?.current, 40)
    }

    func testMockProbeShapeAndAutoSelection() async throws {
        let mock = MockDDCBackend.demo()
        let displays = try await mock.listDisplays()
        XCTAssertEqual(DisplaySelector.preferred(displays)?.id, MockDDCBackend.lenovoID)
        let caps = try await mock.readCapabilities(display: MockDDCBackend.lenovoID)
        XCTAssertTrue(caps?.contains("SIMULATED") == true)
        do {
            _ = try await mock.read(display: MockDDCBackend.lenovoID, code: 0x99)
            XCTFail("expected unsupported")
        } catch let error as DDCError {
            XCTAssertEqual(error, .unsupported(0x99))
        }
        let pinned = try await mock.read(display: MockDDCBackend.lenovoID, code: 0xE0)
        XCTAssertEqual(pinned, VCPValue(current: 40, maximum: 100))
    }

    func testSettingsRoundTripAndCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        var settings = AppSettings.factoryDefaults()
        settings.demoMode = true
        settings.inputBindings[0].value = 0x1B
        settings.inputBindings[0].verifiedOnThisModel = true
        settings.hotkeys = [HotkeyBinding(action: .brightnessUp, keyCode: 126, modifiers: [.command, .option])]
        try store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded, settings)

        try Data("{".utf8).write(to: store.fileURL)
        let recovered = store.load()
        XCTAssertEqual(recovered, .factoryDefaults())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("bad").path))
    }

    func testProfileApplyOrderAgainstTheMock() async throws {
        let mock = MockDDCBackend.demo()
        let controller = DDCController(backend: mock, minIntervalNanoseconds: 0, retryAttempts: 1, retryDelayNanoseconds: 0, sleep: { _ in })
        let night = Profile.builtins().first { $0.name == "Night" }!
        for assignment in ProfilePlan.ordered(night.assignments) {
            try await controller.writeNow(display: MockDDCBackend.lenovoID, code: assignment.code, value: assignment.value)
        }
        let blue = try await mock.read(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.gainBlue)
        let brightness = try await mock.read(display: MockDDCBackend.lenovoID, code: MCCSCatalog.Code.brightness)
        XCTAssertEqual(blue.current, 30)
        XCTAssertEqual(brightness.current, 14)
        let log = await mock.writes(code: MCCSCatalog.Code.brightness, display: MockDDCBackend.lenovoID)
        XCTAssertEqual(log, [14])
    }
}

private actor AttemptCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private final class ValueBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Blocks the first sleep so a test can enqueue a burst inside the coalesce window.
private final class FirstSleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var continuation: CheckedContinuation<Void, Never>?

    func sleep() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if armed {
                lock.unlock()
                continuation.resume()
            } else {
                armed = true
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        armed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
