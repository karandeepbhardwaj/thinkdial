import Foundation

/// VESA MCCS feature names used as labels while probing.
/// A name here means the code exists in the MCCS spec. It does not mean the ThinkVision P34WD-40 implements it.
public enum MCCSCatalog {
    public static let names: [UInt8: String] = [
        0x02: "New control value",
        0x04: "Restore factory defaults",
        0x05: "Restore factory luminance/contrast",
        0x06: "Restore factory geometry",
        0x08: "Restore factory color",
        0x0B: "Color temperature increment",
        0x0C: "Color temperature request",
        0x10: "Brightness",
        0x12: "Contrast",
        0x14: "Select color preset",
        0x16: "Video gain (red)",
        0x18: "Video gain (green)",
        0x1A: "Video gain (blue)",
        0x1C: "Focus",
        0x1E: "Auto setup",
        0x1F: "Auto color setup",
        0x20: "Horizontal position",
        0x30: "Vertical position",
        0x3E: "Clock phase",
        0x52: "Active control",
        0x60: "Input source",
        0x62: "Audio speaker volume",
        0x64: "Audio microphone volume",
        0x66: "Ambient light sensor",
        0x6C: "Video black level (red)",
        0x6E: "Video black level (green)",
        0x70: "Video black level (blue)",
        0x8A: "Audio treble",
        0x8C: "Audio bass",
        0x8D: "Audio mute",
        0x8E: "Audio balance",
        0xAC: "Horizontal frequency",
        0xAE: "Vertical frequency",
        0xB2: "Flat panel sub-pixel layout",
        0xB6: "Display technology type",
        0xC0: "Display usage time",
        0xC6: "Application enable key",
        0xC8: "Display controller type",
        0xC9: "Display firmware level",
        0xCA: "OSD",
        0xCC: "OSD language",
        0xD6: "Power mode",
        0xDC: "Display application",
        0xDF: "VCP version"
    ]

    public static func name(for code: UInt8) -> String? {
        names[code]
    }

    public enum Code {
        public static let brightness: UInt8 = 0x10
        public static let contrast: UInt8 = 0x12
        public static let colorPreset: UInt8 = 0x14
        public static let gainRed: UInt8 = 0x16
        public static let gainGreen: UInt8 = 0x18
        public static let gainBlue: UInt8 = 0x1A
        public static let inputSource: UInt8 = 0x60
        public static let volume: UInt8 = 0x62
        public static let mute: UInt8 = 0x8D
        public static let powerMode: UInt8 = 0xD6
    }
}

public enum VCPMapping {
    /// Some panels answer a continuous code with maximum 0. Sliders then use 100 so the control still moves.
    /// The probe screen keeps showing the reported 0.
    public static func effectiveMaximum(_ reported: UInt16) -> UInt16 {
        reported == 0 ? 100 : reported
    }

    /// `unit` is 0...1. Values outside that range are clamped.
    public static func raw(unit: Double, reportedMaximum: UInt16) -> UInt16 {
        let maximum = effectiveMaximum(reportedMaximum)
        let clamped = min(1, max(0, unit))
        return UInt16((clamped * Double(maximum)).rounded())
    }

    public static func unit(raw: UInt16, reportedMaximum: UInt16) -> Double {
        let maximum = Double(effectiveMaximum(reportedMaximum))
        guard maximum > 0 else { return 0 }
        return min(1, max(0, Double(raw) / maximum))
    }

    public static func percent(raw: UInt16, reportedMaximum: UInt16) -> Int {
        Int((unit(raw: raw, reportedMaximum: reportedMaximum) * 100).rounded())
    }

    public static func raw(percent: Double, reportedMaximum: UInt16) -> UInt16 {
        raw(unit: percent / 100, reportedMaximum: reportedMaximum)
    }
}

/// MCCS mute values. 0x01 mutes, 0x02 unmutes. Other readings are left unrecognized.
public enum MuteMapping {
    public static let mute: UInt16 = 1
    public static let unmute: UInt16 = 2

    public static func isMuted(current: UInt16) -> Bool? {
        switch current {
        case mute: return true
        case unmute: return false
        default: return nil
        }
    }

    public static func value(muted: Bool) -> UInt16 {
        muted ? mute : unmute
    }
}

/// MCCS power-mode values. Neither value has been confirmed on a P34WD-40.
public enum PowerMapping {
    public static let code: UInt8 = MCCSCatalog.Code.powerMode
    /// MCCS: DPM on.
    public static let on: UInt16 = 0x01
    /// MCCS write value used to turn the display off. Often does not wake the panel again.
    public static let off: UInt16 = 0x05
    public static let verifiedOnP34WD40 = false
}
