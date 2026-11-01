import Foundation

public struct VCPAssignment: Codable, Equatable, Sendable {
    public var code: UInt8
    public var value: UInt16

    public init(code: UInt8, value: UInt16) {
        self.code = code
        self.value = value
    }
}

public struct Profile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var detail: String
    public var assignments: [VCPAssignment]

    public init(id: UUID, name: String, symbol: String, detail: String, assignments: [VCPAssignment]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.detail = detail
        self.assignments = assignments
    }

    public static func builtins() -> [Profile] {
        [
            Profile(
                id: UUID(uuidString: "B1C0D100-0000-4000-8000-000000000001")!,
                name: "Coding",
                symbol: "laptopcomputer",
                detail: "Dimmer starting point. 0x05 is the MCCS name for 6500 K, not a measurement of this panel.",
                assignments: [
                    VCPAssignment(code: MCCSCatalog.Code.colorPreset, value: 0x05),
                    VCPAssignment(code: MCCSCatalog.Code.contrast, value: 75),
                    VCPAssignment(code: MCCSCatalog.Code.brightness, value: 45)
                ]
            ),
            Profile(
                id: UUID(uuidString: "B1C0D100-0000-4000-8000-000000000002")!,
                name: "Movie",
                symbol: "film",
                detail: "Brighter starting point. No color preset is included, because this model’s movie preset code is unknown.",
                assignments: [
                    VCPAssignment(code: MCCSCatalog.Code.contrast, value: 68),
                    VCPAssignment(code: MCCSCatalog.Code.brightness, value: 78)
                ]
            ),
            Profile(
                id: UUID(uuidString: "B1C0D100-0000-4000-8000-000000000003")!,
                name: "Night",
                symbol: "moon.stars",
                detail: "Low brightness and a reduced blue gain. Gains are a guess until you probe 0x16 / 0x18 / 0x1A.",
                assignments: [
                    VCPAssignment(code: MCCSCatalog.Code.gainRed, value: 50),
                    VCPAssignment(code: MCCSCatalog.Code.gainGreen, value: 42),
                    VCPAssignment(code: MCCSCatalog.Code.gainBlue, value: 30),
                    VCPAssignment(code: MCCSCatalog.Code.contrast, value: 55),
                    VCPAssignment(code: MCCSCatalog.Code.brightness, value: 14)
                ]
            )
        ]
    }
}

public enum ProfilePlan {
    /// Drop repeated codes, keeping the last value, and keep that value in its last position.
    /// Built-in profiles put the color preset before brightness so a preset that resets brightness does not win.
    public static func ordered(_ assignments: [VCPAssignment]) -> [VCPAssignment] {
        var seen: Set<UInt8> = []
        var reversed: [VCPAssignment] = []
        for assignment in assignments.reversed() {
            if seen.contains(assignment.code) { continue }
            seen.insert(assignment.code)
            reversed.append(assignment)
        }
        return reversed.reversed()
    }
}
