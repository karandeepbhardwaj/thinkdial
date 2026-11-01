import AppIntents
import Foundation
import ThinkDialCore

struct SetBrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Set ThinkDial Brightness"
    static var description = IntentDescription("Sets the external monitor brightness. 0 is the dimmest step and 100 is the brightest.")
    static var openAppWhenRun = true

    @Parameter(title: "Percent", default: 50)
    var percent: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clamped = min(100, max(0, percent))
        await AppModel.shared.commitSlider(.brightness, percent: Double(clamped))
        return .result(dialog: "Brightness \(clamped).")
    }
}

struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set ThinkDial Volume"
    static var description = IntentDescription("Sets the monitor speaker volume from 0 to 100.")
    static var openAppWhenRun = true

    @Parameter(title: "Percent", default: 20)
    var percent: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clamped = min(100, max(0, percent))
        await AppModel.shared.commitSlider(.volume, percent: Double(clamped))
        return .result(dialog: "Volume \(clamped).")
    }
}

struct ToggleMuteIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle ThinkDial Mute"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppModel.shared.toggleMute()
        let muted = await AppModel.shared.muted
        return .result(dialog: muted == true ? "Muted." : "Unmuted.")
    }
}

struct ApplyProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply ThinkDial Profile"
    static var openAppWhenRun = true

    @Parameter(title: "Profile")
    var profileName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppModel.shared.start()
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let profiles = await AppModel.shared.settings.profiles
        guard let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw DDCError.invalidValue("No profile named \(profileName).")
        }
        await AppModel.shared.apply(profile: profile)
        return .result(dialog: "Applied \(profile.name).")
    }
}

enum ThinkDialInputChoice: String, AppEnum {
    case usbC
    case displayPort
    case hdmi

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Input")
    static var caseDisplayRepresentations: [ThinkDialInputChoice: DisplayRepresentation] = [
        .usbC: DisplayRepresentation(title: "USB-C"),
        .displayPort: DisplayRepresentation(title: "DisplayPort"),
        .hdmi: DisplayRepresentation(title: "HDMI")
    ]

    var bindingID: String {
        switch self {
        case .usbC: return InputBinding.usbC
        case .displayPort: return InputBinding.displayPort
        case .hdmi: return InputBinding.hdmi
        }
    }
}

struct SwitchInputIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch ThinkDial Input"
    static var description = IntentDescription("Switches the monitor input using the value saved in ThinkDial. Switching away from this Mac can cut DDC.")
    static var openAppWhenRun = true

    @Parameter(title: "Input")
    var input: ThinkDialInputChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppModel.shared.start()
        let settings = await AppModel.shared.settings
        guard let binding = settings.binding(input.bindingID), let value = binding.value else {
            throw DDCError.invalidValue("That input has no saved value yet. Set one in ThinkDial first.")
        }
        try await AppModel.shared.writeNow(code: MCCSCatalog.Code.inputSource, value: value)
        return .result(dialog: "Asked for \(binding.title) (\(VCPText.format(value))).")
    }
}

struct PowerOffDisplayIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn ThinkDial Display Off"
    static var description = IntentDescription("Writes the MCCS power-off value. The panel may not wake over DDC.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The no-argument requestConfirmation() is easy to make ambiguous against the
        // later overloads. This one has been the stable dialog form since macOS 15.
        if #available(macOS 15.0, *) {
            try await requestConfirmation(
                actionName: .`continue`,
                dialog: IntentDialog("Turn the ThinkVision off? This writes VCP 0xD6 = 0x05. DDC often cannot wake the panel.")
            )
        }
        try await AppModel.shared.writeNow(code: PowerMapping.code, value: PowerMapping.off)
        return .result(dialog: "Sent power off.")
    }
}

struct ThinkDialShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: ["Set \(.applicationName) brightness to \(\.$percent)"],
            shortTitle: "Set brightness",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: ApplyProfileIntent(),
            phrases: ["Apply \(\.$profileName) with \(.applicationName)"],
            shortTitle: "Apply profile",
            systemImageName: "square.stack"
        )
        AppShortcut(
            intent: SwitchInputIntent(),
            phrases: ["Switch \(.applicationName) input to \(\.$input)"],
            shortTitle: "Switch input",
            systemImageName: "arrow.left.arrow.right"
        )
    }
}
