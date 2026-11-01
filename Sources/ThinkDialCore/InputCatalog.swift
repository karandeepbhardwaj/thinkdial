import Foundation

public enum ValueBasis: String, Codable, Equatable, Sendable {
    /// The number is the one printed in the VESA MCCS spec for that feature.
    case mccs
    /// Reported for a different vendor's USB-C implementation. Not a P34WD-40 measurement.
    case otherVendorReport
    /// Reported for an older Lenovo panel. Not a P34WD-40 measurement.
    case olderLenovoReport
    case userAssigned
    case discovered
}

public struct InputCandidate: Identifiable, Equatable, Codable, Sendable {
    public var value: UInt16
    public var label: String
    public var basis: ValueBasis
    public var note: String
    /// Always false until someone confirms the code on a P34WD-40 and changes this deliberately.
    public var verifiedOnP34WD40: Bool

    public var id: UInt16 { value }

    public init(value: UInt16, label: String, basis: ValueBasis, note: String, verifiedOnP34WD40: Bool = false) {
        self.value = value
        self.label = label
        self.basis = basis
        self.note = note
        self.verifiedOnP34WD40 = verifiedOnP34WD40
    }
}

public enum InputCandidateCatalog {
    public static let disconnectWarning = "Switching the input can blank this Mac and cut DDC until you change the input back from the monitor's buttons or from another computer."

    /// Candidates to try, not a map of the P34WD-40. None of these are verified on this model.
    public static let all: [InputCandidate] = [
        InputCandidate(value: 0x0F, label: "DisplayPort-1", basis: .mccs, note: "MCCS input 0x0F. Not confirmed on the P34WD-40."),
        InputCandidate(value: 0x10, label: "DisplayPort-2", basis: .mccs, note: "MCCS input 0x10. Not confirmed on the P34WD-40."),
        InputCandidate(value: 0x11, label: "HDMI-1", basis: .mccs, note: "MCCS input 0x11. Not confirmed on the P34WD-40."),
        InputCandidate(value: 0x12, label: "HDMI-2", basis: .mccs, note: "MCCS input 0x12. Not confirmed on the P34WD-40."),
        InputCandidate(value: 0x13, label: "Unspecified 0x13", basis: .olderLenovoReport, note: "An older Lenovo P44w-10 has been reported using 0x13. Not confirmed on the P34WD-40."),
        InputCandidate(value: 0x14, label: "Unspecified 0x14", basis: .olderLenovoReport, note: "An older Lenovo P44w-10 has been reported using 0x14. Not confirmed on the P34WD-40."),
        InputCandidate(value: 0x1B, label: "Unspecified 0x1B", basis: .otherVendorReport, note: "Some Dell USB-C ports use 0x1B. Not confirmed on the P34WD-40.")
    ]

    public static func candidate(value: UInt16) -> InputCandidate? {
        all.first { $0.value == value }
    }
}

public enum InputSwitchPolicy {
    public static func allows(confirmed: Bool) -> Bool {
        confirmed
    }
}

public struct InputBinding: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    /// Nil until the user sets or discovers a value. USB-C ships unset on purpose.
    public var value: UInt16?
    public var verifiedOnThisModel: Bool
    public var note: String

    public init(id: String, title: String, symbol: String, value: UInt16?, verifiedOnThisModel: Bool, note: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.value = value
        self.verifiedOnThisModel = verifiedOnThisModel
        self.note = note
    }

    public static let usbC = "usbc"
    public static let displayPort = "displayport"
    public static let hdmi = "hdmi"

    public static func factoryDefaults() -> [InputBinding] {
        [
            InputBinding(
                id: usbC,
                title: "USB-C",
                symbol: "cable.connector",
                value: nil,
                verifiedOnThisModel: false,
                note: "No MCCS code is defined for USB-C. Set this after the input tester, or type a value you have checked."
            ),
            InputBinding(
                id: displayPort,
                title: "DisplayPort",
                symbol: "dpad.right.filled",
                value: 0x0F,
                verifiedOnThisModel: false,
                note: "Starts at MCCS DisplayPort-1 (0x0F). The P34WD-40 has not been confirmed to use it. Edit it if the tester finds another value."
            ),
            InputBinding(
                id: hdmi,
                title: "HDMI",
                symbol: "hifispeaker",
                value: 0x11,
                verifiedOnThisModel: false,
                note: "Starts at MCCS HDMI-1 (0x11). The P34WD-40 has not been confirmed to use it."
            )
        ]
    }
}

public struct LabeledValue: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var value: UInt16
    public var label: String
    public var verifiedOnThisModel: Bool
    public var note: String

    public var id: UInt16 { value }

    public init(value: UInt16, label: String, verifiedOnThisModel: Bool = false, note: String) {
        self.value = value
        self.label = label
        self.verifiedOnThisModel = verifiedOnThisModel
        self.note = note
    }
}

public enum ColorPresets {
    /// MCCS select-color-preset names for VCP 0x14. The panel may implement only some of them.
    public static func mccsDefaults() -> [LabeledValue] {
        let note = "MCCS name for VCP 0x14. Not confirmed on the P34WD-40."
        return [
            LabeledValue(value: 0x01, label: "sRGB", note: note),
            LabeledValue(value: 0x02, label: "Native", note: note),
            LabeledValue(value: 0x04, label: "5000 K", note: note),
            LabeledValue(value: 0x05, label: "6500 K", note: note),
            LabeledValue(value: 0x06, label: "7500 K", note: note),
            LabeledValue(value: 0x08, label: "9300 K", note: note),
            LabeledValue(value: 0x0B, label: "User 1", note: note),
            LabeledValue(value: 0x0C, label: "User 2", note: note),
            LabeledValue(value: 0x0D, label: "User 3", note: note)
        ]
    }
}
