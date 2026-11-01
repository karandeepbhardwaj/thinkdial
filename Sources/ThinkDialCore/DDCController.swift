import Foundation

public struct WriteKey: Hashable, Sendable {
    public var display: DisplayID
    public var code: UInt8

    public init(display: DisplayID, code: UInt8) {
        self.display = display
        self.code = code
    }
}

public enum DDCControllerEvent: Equatable, Sendable {
    case writeSucceeded(display: String, code: UInt8, value: UInt16)
    case writeFailed(display: String, code: UInt8, message: String)
}

/// Serializes DDC traffic, coalesces slider writes, and retries failed operations.
/// Slider traffic should go through `enqueueWrite`. Input changes, profiles, and power use `writeNow`.
public actor DDCController {
    private var backend: any DDCBackend
    private var pending: [WriteKey: UInt16] = [:]
    private var drainTask: Task<Void, Never>?
    private var lastBusWrite: ContinuousClock.Instant?
    private var minIntervalNanoseconds: UInt64
    private var retryAttempts: Int
    private let retryDelayNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void
    private let events: @Sendable (DDCControllerEvent) -> Void

    public init(
        backend: any DDCBackend,
        minIntervalNanoseconds: UInt64 = 80_000_000,
        retryAttempts: Int = 3,
        retryDelayNanoseconds: UInt64 = 40_000_000,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        events: @escaping @Sendable (DDCControllerEvent) -> Void = { _ in }
    ) {
        self.backend = backend
        self.minIntervalNanoseconds = minIntervalNanoseconds
        self.retryAttempts = max(1, retryAttempts)
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.sleep = sleep
        self.events = events
    }

    public func setTiming(minIntervalNanoseconds: UInt64, retryAttempts: Int) {
        self.minIntervalNanoseconds = minIntervalNanoseconds
        self.retryAttempts = max(1, retryAttempts)
    }

    public func replaceBackend(_ backend: any DDCBackend) {
        self.backend = backend
    }

    public func enqueueWrite(display: DisplayID, code: UInt8, value: UInt16) {
        pending[WriteKey(display: display, code: code)] = value
        startDrainIfNeeded()
    }

    public func writeNow(display: DisplayID, code: UInt8, value: UInt16) async throws {
        let key = WriteKey(display: display, code: code)
        pending.removeValue(forKey: key)
        await paceBus()
        let backend = self.backend
        let attempts = retryAttempts
        let delay = retryDelayNanoseconds
        let sleep = self.sleep
        do {
            try await Retry.run(attempts: attempts, delayNanoseconds: delay, sleep: sleep) {
                try await backend.write(display: display, code: code, value: value)
            }
            lastBusWrite = .now
            events(.writeSucceeded(display: display.raw, code: code, value: value))
        } catch {
            events(.writeFailed(display: display.raw, code: code, message: String(describing: error)))
            throw error
        }
    }

    public func read(display: DisplayID, code: UInt8, attempts: Int? = nil) async throws -> VCPValue {
        let key = WriteKey(display: display, code: code)
        if pending[key] != nil {
            startDrainIfNeeded()
            var spins = 0
            while pending[key] != nil, spins < 8, let task = drainTask {
                await task.value
                spins += 1
            }
        }
        let backend = self.backend
        let tries = max(1, attempts ?? retryAttempts)
        let delay = retryDelayNanoseconds
        let sleep = self.sleep
        return try await Retry.run(attempts: tries, delayNanoseconds: delay, sleep: sleep) {
            try await backend.read(display: display, code: code)
        }
    }

    public func readCapabilities(display: DisplayID) async throws -> String? {
        let backend = self.backend
        return try await backend.readCapabilities(display: display)
    }

    public func listDisplays() async throws -> [DisplayDescriptor] {
        try await backend.listDisplays()
    }

    /// Waits until queued slider writes have been sent.
    public func flush() async {
        var spins = 0
        while let task = drainTask, spins < 32 {
            await task.value
            spins += 1
        }
    }

    private func startDrainIfNeeded() {
        if drainTask == nil {
            drainTask = Task { await self.drain() }
        }
    }

    private func drain() async {
        // The opening sleep is the coalesce window: slider events that arrive during it
        // overwrite `pending`, so the bus sees the latest value instead of every tick.
        while !pending.isEmpty {
            await sleep(minIntervalNanoseconds)
            if pending.isEmpty { break }
            let batch = pending
            pending.removeAll()
            let keys = batch.keys.sorted { lhs, rhs in
                if lhs.display != rhs.display { return lhs.display < rhs.display }
                return lhs.code < rhs.code
            }
            for key in keys {
                guard let original = batch[key] else { continue }
                await paceBus()
                let value = pending.removeValue(forKey: key) ?? original
                await performWrite(key: key, value: value)
            }
        }
        drainTask = nil
        if !pending.isEmpty {
            startDrainIfNeeded()
        }
    }

    private func performWrite(key: WriteKey, value: UInt16) async {
        let backend = self.backend
        let attempts = retryAttempts
        let delay = retryDelayNanoseconds
        let sleep = self.sleep
        lastBusWrite = .now
        do {
            try await Retry.run(attempts: attempts, delayNanoseconds: delay, sleep: sleep) {
                try await backend.write(display: key.display, code: key.code, value: value)
            }
            events(.writeSucceeded(display: key.display.raw, code: key.code, value: value))
        } catch {
            events(.writeFailed(display: key.display.raw, code: key.code, message: String(describing: error)))
        }
    }

    private func paceBus() async {
        guard minIntervalNanoseconds > 0, let last = lastBusWrite else { return }
        let elapsed = ContinuousClock.now - last
        let needed = Duration.nanoseconds(Int64(min(minIntervalNanoseconds, UInt64(Int64.max))))
        guard elapsed < needed else { return }
        let rest = needed - elapsed
        let (seconds, attoseconds) = rest.components
        let nanoseconds = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
        if nanoseconds > 0 {
            await sleep(UInt64(nanoseconds))
        }
    }
}
