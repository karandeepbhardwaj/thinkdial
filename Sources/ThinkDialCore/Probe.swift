import Foundation

public struct ProbeReading: Codable, Equatable, Sendable {
    public var code: UInt8
    public var responded: Bool
    public var current: UInt16?
    public var maximum: UInt16?
    public var message: String?

    public init(code: UInt8, responded: Bool, current: UInt16?, maximum: UInt16?, message: String?) {
        self.code = code
        self.responded = responded
        self.current = current
        self.maximum = maximum
        self.message = message
    }
}

public enum ProbeInterpreter {
    public static func reading(code: UInt8, result: Result<VCPValue, Error>) -> ProbeReading {
        switch result {
        case .success(let value):
            return ProbeReading(code: code, responded: true, current: value.current, maximum: value.maximum, message: nil)
        case .failure(let error):
            return ProbeReading(code: code, responded: false, current: nil, maximum: nil, message: String(describing: error))
        }
    }
}

public struct ProbeRow: Identifiable, Codable, Equatable, Sendable {
    public var code: UInt8
    public var inCapabilities: Bool
    public var capabilityValues: [UInt8]
    public var responded: Bool
    public var current: UInt16?
    public var maximum: UInt16?
    public var mccsName: String?
    public var label: String

    public var id: UInt8 { code }

    public init(
        code: UInt8,
        inCapabilities: Bool,
        capabilityValues: [UInt8],
        responded: Bool,
        current: UInt16?,
        maximum: UInt16?,
        mccsName: String?,
        label: String
    ) {
        self.code = code
        self.inCapabilities = inCapabilities
        self.capabilityValues = capabilityValues
        self.responded = responded
        self.current = current
        self.maximum = maximum
        self.mccsName = mccsName
        self.label = label
    }
}

public enum ProbeMerge {
    /// Rows the probe screen shows by default: codes that answered, or codes named in the capabilities string.
    public static func rows(
        capabilities: ParsedCapabilities?,
        readings: [ProbeReading],
        labels: [UInt8: String]
    ) -> [ProbeRow] {
        var byCode: [UInt8: ProbeReading] = [:]
        for reading in readings {
            byCode[reading.code] = reading
        }
        var codes = Set(byCode.filter { $0.value.responded }.map(\.key))
        var featureValues: [UInt8: [UInt8]] = [:]
        if let capabilities {
            for feature in capabilities.features {
                codes.insert(feature.code)
                featureValues[feature.code] = feature.values
            }
        }
        return codes.sorted().map { code in
            let reading = byCode[code]
            return ProbeRow(
                code: code,
                inCapabilities: featureValues[code] != nil || (capabilities?.feature(code) != nil),
                capabilityValues: featureValues[code] ?? [],
                responded: reading?.responded ?? false,
                current: reading?.current,
                maximum: reading?.maximum,
                mccsName: MCCSCatalog.name(for: code),
                label: labels[code] ?? ""
            )
        }
    }
}

public enum ControlKind: String, Codable, Equatable, Sendable, CaseIterable {
    case slider
    case toggle
    case picker
}

public struct PickerChoice: Codable, Equatable, Sendable, Identifiable {
    public var value: UInt16
    public var label: String

    public var id: UInt16 { value }

    public init(value: UInt16, label: String) {
        self.value = value
        self.label = label
    }
}

public struct CustomControl: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var code: UInt8
    public var label: String
    public var kind: ControlKind
    public var minimum: UInt16
    public var maximum: UInt16
    public var toggleOn: UInt16
    public var toggleOff: UInt16
    public var choices: [PickerChoice]

    public init(
        id: UUID = UUID(),
        code: UInt8,
        label: String,
        kind: ControlKind,
        minimum: UInt16 = 0,
        maximum: UInt16 = 100,
        toggleOn: UInt16 = 1,
        toggleOff: UInt16 = 0,
        choices: [PickerChoice] = []
    ) {
        self.id = id
        self.code = code
        self.label = label
        self.kind = kind
        self.minimum = minimum
        self.maximum = maximum
        self.toggleOn = toggleOn
        self.toggleOff = toggleOff
        self.choices = choices
    }

    public static func pinned(from row: ProbeRow, kind: ControlKind, label: String) -> CustomControl {
        let maximum = row.maximum ?? 100
        let choices = row.capabilityValues.map { value in
            PickerChoice(value: UInt16(value), label: VCPText.format(UInt16(value)))
        }
        return CustomControl(
            code: row.code,
            label: label.isEmpty ? (row.mccsName ?? "VCP \(VCPText.formatCode(row.code))") : label,
            kind: kind,
            minimum: 0,
            maximum: maximum == 0 ? 100 : maximum,
            choices: choices
        )
    }
}

public struct CodeLabel: Codable, Equatable, Sendable {
    public var code: UInt8
    public var label: String

    public init(code: UInt8, label: String) {
        self.code = code
        self.label = label
    }
}

public struct ProbeReport: Codable, Equatable, Sendable {
    public static let currentSchema = 1
    public static let disclaimer = "These readings are what this connection returned. They are not a Lenovo specification for the ThinkVision P34WD-40."

    public var schemaVersion: Int
    public var disclaimer: String
    public var displayName: String
    public var displayID: String
    public var capturedAt: Date
    public var capabilitiesRaw: String?
    public var readings: [ProbeReading]
    public var labels: [CodeLabel]
    public var pinnedControls: [CustomControl]

    public init(
        schemaVersion: Int = ProbeReport.currentSchema,
        disclaimer: String = ProbeReport.disclaimer,
        displayName: String,
        displayID: String,
        capturedAt: Date,
        capabilitiesRaw: String?,
        readings: [ProbeReading],
        labels: [CodeLabel],
        pinnedControls: [CustomControl]
    ) {
        self.schemaVersion = schemaVersion
        self.disclaimer = disclaimer
        self.displayName = displayName
        self.displayID = displayID
        self.capturedAt = capturedAt
        self.capabilitiesRaw = capabilitiesRaw
        self.readings = readings
        self.labels = labels
        self.pinnedControls = pinnedControls
    }

    public var labelMap: [UInt8: String] {
        Dictionary(labels.map { ($0.code, $0.label) }, uniquingKeysWith: { _, last in last })
    }
}

public enum ProbeWritePolicy {
    public static let armingWarning = "Arming writes lets this screen send Set VCP commands. A wrong code can change a picture setting or, for input and power, blank the display. Reads stay available either way."

    public static func allows(armed: Bool, confirmedThisWrite: Bool) -> Bool {
        armed && confirmedThisWrite
    }
}

public enum ProbeLibrary {
    public static func mergePins(existing: [CustomControl], imported: [CustomControl]) -> [CustomControl] {
        var merged = existing
        for control in imported {
            if let index = merged.firstIndex(where: { $0.code == control.code }) {
                var replacement = control
                replacement.id = merged[index].id
                merged[index] = replacement
            } else {
                merged.append(control)
            }
        }
        return merged
    }
}

public enum ProbeExport {
    public static func encode(_ report: ProbeReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    public static func decode(_ data: Data) throws -> ProbeReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ProbeReport.self, from: data)
        guard report.schemaVersion == ProbeReport.currentSchema else {
            throw DDCError.invalidValue("This probe file uses schema \(report.schemaVersion). ThinkDial reads schema \(ProbeReport.currentSchema).")
        }
        return report
    }
}
