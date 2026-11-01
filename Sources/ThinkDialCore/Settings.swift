import Foundation

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public var rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)

    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

public enum HotkeyAction: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case toggleMute

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brightnessUp: return "Brightness up"
        case .brightnessDown: return "Brightness down"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .toggleMute: return "Mute"
        }
    }
}

public struct HotkeyBinding: Codable, Equatable, Sendable, Identifiable {
    public var action: HotkeyAction
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public var id: HotkeyAction { action }

    public init(action: HotkeyAction, keyCode: UInt16, modifiers: KeyModifiers) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schemaVersion: Int
    public var demoMode: Bool
    public var selectedDisplayID: String?
    public var launchAtLogin: Bool
    public var writeMinIntervalMilliseconds: Int
    public var retryAttempts: Int
    public var inputBindings: [InputBinding]
    public var colorPresets: [LabeledValue]
    public var profiles: [Profile]
    public var customControls: [CustomControl]
    public var scheduleMode: ScheduleMode
    public var schedulePoints: [SchedulePoint]
    public var solar: SolarSchedule
    public var scheduleHoldoffSeconds: TimeInterval
    public var hotkeys: [HotkeyBinding]
    public var mapMediaKeys: Bool
    public var brightnessStep: UInt16
    public var volumeStep: UInt16
    public var lastProbe: ProbeReport?

    public init(
        schemaVersion: Int,
        demoMode: Bool,
        selectedDisplayID: String?,
        launchAtLogin: Bool,
        writeMinIntervalMilliseconds: Int,
        retryAttempts: Int,
        inputBindings: [InputBinding],
        colorPresets: [LabeledValue],
        profiles: [Profile],
        customControls: [CustomControl],
        scheduleMode: ScheduleMode,
        schedulePoints: [SchedulePoint],
        solar: SolarSchedule,
        scheduleHoldoffSeconds: TimeInterval,
        hotkeys: [HotkeyBinding],
        mapMediaKeys: Bool,
        brightnessStep: UInt16,
        volumeStep: UInt16,
        lastProbe: ProbeReport?
    ) {
        self.schemaVersion = schemaVersion
        self.demoMode = demoMode
        self.selectedDisplayID = selectedDisplayID
        self.launchAtLogin = launchAtLogin
        self.writeMinIntervalMilliseconds = writeMinIntervalMilliseconds
        self.retryAttempts = retryAttempts
        self.inputBindings = inputBindings
        self.colorPresets = colorPresets
        self.profiles = profiles
        self.customControls = customControls
        self.scheduleMode = scheduleMode
        self.schedulePoints = schedulePoints
        self.solar = solar
        self.scheduleHoldoffSeconds = scheduleHoldoffSeconds
        self.hotkeys = hotkeys
        self.mapMediaKeys = mapMediaKeys
        self.brightnessStep = brightnessStep
        self.volumeStep = volumeStep
        self.lastProbe = lastProbe
    }

    public static func factoryDefaults() -> AppSettings {
        AppSettings(
            schemaVersion: currentSchema,
            demoMode: false,
            selectedDisplayID: nil,
            launchAtLogin: false,
            writeMinIntervalMilliseconds: 80,
            retryAttempts: 3,
            inputBindings: InputBinding.factoryDefaults(),
            colorPresets: ColorPresets.mccsDefaults(),
            profiles: Profile.builtins(),
            customControls: [],
            scheduleMode: .off,
            schedulePoints: [
                SchedulePoint(minutesFromMidnight: 7 * 60 + 30, brightness: 55),
                SchedulePoint(minutesFromMidnight: 12 * 60 + 30, brightness: 70),
                SchedulePoint(minutesFromMidnight: 18 * 60 + 30, brightness: 40),
                SchedulePoint(minutesFromMidnight: 22 * 60, brightness: 18)
            ],
            solar: .unset,
            scheduleHoldoffSeconds: 120,
            hotkeys: [],
            mapMediaKeys: false,
            brightnessStep: 6,
            volumeStep: 6,
            lastProbe: nil
        )
    }

    public func binding(_ id: String) -> InputBinding? {
        inputBindings.first { $0.id == id }
    }
}

public struct SettingsStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func live() -> SettingsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("ThinkDial", isDirectory: true)
        return SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .factoryDefaults()
        }
        do {
            return try Self.decoder.decode(AppSettings.self, from: data)
        } catch {
            let backup = fileURL.appendingPathExtension("bad")
            try? data.write(to: backup, options: .atomic)
            return .factoryDefaults()
        }
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
