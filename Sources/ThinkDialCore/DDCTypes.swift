import Foundation

/// Stable id for a connected display. Apple Silicon uses the EDID UUID or IORegistry path.
public struct DisplayID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public var description: String { raw }

    public static func < (lhs: DisplayID, rhs: DisplayID) -> Bool {
        lhs.raw < rhs.raw
    }
}

public struct DisplayDescriptor: Identifiable, Hashable, Codable, Sendable {
    public var id: DisplayID
    public var name: String
    public var vendor: String
    public var productName: String
    public var serialNumber: String
    public var transport: String
    public var isBuiltIn: Bool
    /// False when the display is visible to macOS but no DDC service was found for it.
    public var ddcAvailable: Bool

    public init(
        id: DisplayID,
        name: String,
        vendor: String,
        productName: String,
        serialNumber: String,
        transport: String,
        isBuiltIn: Bool,
        ddcAvailable: Bool
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.productName = productName
        self.serialNumber = serialNumber
        self.transport = transport
        self.isBuiltIn = isBuiltIn
        self.ddcAvailable = ddcAvailable
    }
}

public struct VCPValue: Equatable, Hashable, Codable, Sendable {
    public var current: UInt16
    public var maximum: UInt16

    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }
}

public enum DDCError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case notConnected
    case unsupported(UInt8)
    case readFailed(UInt8)
    case writeFailed(UInt8)
    case invalidValue(String)
    case cancelled

    public var description: String {
        switch self {
        case .notConnected:
            return "No DDC connection to that display."
        case .unsupported(let code):
            return String(format: "VCP 0x%02X did not respond.", code)
        case .readFailed(let code):
            return String(format: "Reading VCP 0x%02X failed.", code)
        case .writeFailed(let code):
            return String(format: "Writing VCP 0x%02X failed.", code)
        case .invalidValue(let message):
            return message
        case .cancelled:
            return "Cancelled."
        }
    }

    public var errorDescription: String? { description }
}

public protocol DDCBackend: Sendable {
    func listDisplays() async throws -> [DisplayDescriptor]
    func read(display: DisplayID, code: UInt8) async throws -> VCPValue
    func write(display: DisplayID, code: UInt8, value: UInt16) async throws
    func readCapabilities(display: DisplayID) async throws -> String?
}

public extension DDCBackend {
    func readCapabilities(display: DisplayID) async throws -> String? {
        nil
    }
}

/// Swaps the live backend (hardware or demo) without rebuilding the write scheduler.
public final class SwitchingBackend: DDCBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var inner: any DDCBackend

    public init(_ inner: any DDCBackend) {
        self.inner = inner
    }

    public func replace(with backend: any DDCBackend) {
        lock.lock()
        inner = backend
        lock.unlock()
    }

    private func current() -> any DDCBackend {
        lock.lock()
        defer { lock.unlock() }
        return inner
    }

    public func listDisplays() async throws -> [DisplayDescriptor] {
        try await current().listDisplays()
    }

    public func read(display: DisplayID, code: UInt8) async throws -> VCPValue {
        try await current().read(display: display, code: code)
    }

    public func write(display: DisplayID, code: UInt8, value: UInt16) async throws {
        try await current().write(display: display, code: code, value: value)
    }

    public func readCapabilities(display: DisplayID) async throws -> String? {
        try await current().readCapabilities(display: display)
    }
}

public enum DisplayList {
    /// Keep one descriptor per id. A later entry wins when it is the one that can speak DDC.
    public static func deduplicated(_ displays: [DisplayDescriptor]) -> [DisplayDescriptor] {
        var best: [DisplayID: DisplayDescriptor] = [:]
        for display in displays {
            if let existing = best[display.id] {
                if display.ddcAvailable && !existing.ddcAvailable {
                    best[display.id] = display
                }
            } else {
                best[display.id] = display
            }
        }
        return best.values.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame {
                return lhs.id < rhs.id
            }
            return order == .orderedAscending
        }
    }
}

public enum VCPText {
    /// Accepts `0x1B`, `x1B`, or a decimal number. `max` is inclusive.
    public static func parse(_ raw: String, max: UInt16 = .max) -> UInt16? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let value: UInt16?
        let lower = trimmed.lowercased()
        if lower.hasPrefix("0x") {
            value = UInt16(lower.dropFirst(2), radix: 16)
        } else if lower.hasPrefix("x") {
            value = UInt16(lower.dropFirst(1), radix: 16)
        } else {
            value = UInt16(lower, radix: 10)
        }
        guard let value, value <= max else { return nil }
        return value
    }

    public static func format(_ value: UInt16) -> String {
        String(format: "0x%02X", value)
    }

    public static func formatCode(_ code: UInt8) -> String {
        String(format: "0x%02X", code)
    }
}

public enum TimingLimits {
    public static func intervalMilliseconds(_ value: Int) -> Int {
        min(5_000, max(20, value))
    }

    public static func attempts(_ value: Int) -> Int {
        min(6, max(1, value))
    }
}
