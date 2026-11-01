import Combine
import Foundation
import ThinkDialCore

enum SliderID: Hashable {
    case brightness
    case contrast
    case volume
    case red
    case green
    case blue
}

struct SliderState: Equatable {
    var percent: Double = 50
    var raw: UInt16 = 50
    var reportedMax: UInt16 = 100
}

enum SettingsPage: Hashable {
    case general
    case inputs
    case color
    case hotkeys
    case schedule
    case about
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: AppSettings
    @Published var displays: [DisplayDescriptor] = []
    @Published var active: DisplayDescriptor?
    @Published var brightness = SliderState(percent: 40, raw: 40, reportedMax: 100)
    @Published var contrast = SliderState(percent: 70, raw: 70, reportedMax: 100)
    @Published var volume = SliderState(percent: 20, raw: 20, reportedMax: 100)
    @Published var red = SliderState()
    @Published var green = SliderState()
    @Published var blue = SliderState()
    @Published var colorPreset: UInt16 = 0x05
    @Published var muted: Bool?
    @Published var customValues: [UInt8: UInt16] = [:]
    @Published var banner: String?
    @Published var isRefreshing = false
    @Published var settingsPage: SettingsPage = .general
    @Published var mediaKeysActive = false

    let switching: SwitchingBackend
    let controller: DDCController
    private let store: SettingsStore
    private let hotkeys = HotkeyCenter()
    private var mediaKeys: MediaKeyMonitor?
    private var timer: Timer?
    private var startTask: Task<Void, Never>?
    private var lastManualBrightness: Date?

    private init() {
        let store = SettingsStore.live()
        let settings = store.load()
        self.store = store
        self.settings = settings
        let backend: any DDCBackend = settings.demoMode
            ? MockDDCBackend.demo(delayNanoseconds: 1_500_000)
            : HardwareDDCBackend()
        switching = SwitchingBackend(backend)
        controller = DDCController(
            backend: switching,
            minIntervalNanoseconds: UInt64(TimingLimits.intervalMilliseconds(settings.writeMinIntervalMilliseconds)) * 1_000_000,
            retryAttempts: TimingLimits.attempts(settings.retryAttempts),
            events: { event in
                Task { @MainActor in
                    AppModel.shared.handle(event)
                }
            }
        )
    }

    var demoMode: Bool { settings.demoMode }

    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor in
            await self.startBody()
        }
        startTask = task
        await task.value
    }

    private func startBody() async {
        installHotkeys()
        installMediaKeys()
        await refresh()
        await applyScheduleIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                await AppModel.shared.applyScheduleIfNeeded()
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let found = DisplayList.deduplicated(try await controller.listDisplays())
            displays = found
            active = DisplaySelector.resolve(displays: found, pinnedID: settings.selectedDisplayID)
            guard let active else {
                banner = settings.demoMode ? nil : "No DDC display yet. Connect the ThinkVision with USB-C or DisplayPort, or open demo mode."
                return
            }
            banner = nil
            await readCurrentValues(for: active.id)
        } catch {
            banner = error.localizedDescription
        }
    }

    func select(display: DisplayDescriptor) async {
        settings.selectedDisplayID = display.id.raw
        save()
        active = display
        await readCurrentValues(for: display.id)
    }

    func useAutomaticDisplay() async {
        settings.selectedDisplayID = nil
        save()
        active = DisplaySelector.preferred(displays)
        if let active {
            await readCurrentValues(for: active.id)
        }
    }

    func setDemoMode(_ enabled: Bool) async {
        settings.demoMode = enabled
        save()
        let backend: any DDCBackend = enabled
            ? MockDDCBackend.demo(delayNanoseconds: 1_500_000)
            : HardwareDDCBackend()
        switching.replace(with: backend)
        await controller.flush()
        await refresh()
    }

    func commitSlider(_ id: SliderID, percent: Double) {
        guard let display = active, display.ddcAvailable || settings.demoMode else { return }
        var state = slider(id)
        let raw = VCPMapping.raw(percent: percent, reportedMaximum: state.reportedMax)
        state.percent = min(100, max(0, percent))
        state.raw = raw
        setSlider(id, state)
        if id == .brightness { lastManualBrightness = Date() }
        let code = vcpCode(id)
        let displayID = display.id
        Task { await controller.enqueueWrite(display: displayID, code: code, value: raw) }
    }

    func stepBrightness(by delta: Int) {
        commitSlider(.brightness, percent: brightness.percent + Double(delta))
    }

    func stepVolume(by delta: Int) {
        commitSlider(.volume, percent: volume.percent + Double(delta))
    }

    func toggleMute() {
        let next = !(muted ?? false)
        muted = next
        guard let display = active else { return }
        let value = MuteMapping.value(muted: next)
        let displayID = display.id
        Task { await controller.enqueueWrite(display: displayID, code: MCCSCatalog.Code.mute, value: value) }
    }

    func commitPreset(_ value: UInt16) {
        colorPreset = value
        guard let display = active else { return }
        let displayID = display.id
        Task { await controller.enqueueWrite(display: displayID, code: MCCSCatalog.Code.colorPreset, value: value) }
    }

    func commitCustom(code: UInt8, value: UInt16) {
        customValues[code] = value
        guard let display = active else { return }
        let displayID = display.id
        Task { await controller.enqueueWrite(display: displayID, code: code, value: value) }
    }

    func writeNow(code: UInt8, value: UInt16) async throws {
        guard let display = active else { throw DDCError.notConnected }
        try await controller.writeNow(display: display.id, code: code, value: value)
        if code == MCCSCatalog.Code.inputSource || code == MCCSCatalog.Code.powerMode || code == MCCSCatalog.Code.colorPreset {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await readCurrentValues(for: display.id)
        }
    }

    func readCode(_ code: UInt8) async throws -> VCPValue {
        guard let display = active else { throw DDCError.notConnected }
        return try await controller.read(display: display.id, code: code, attempts: 1)
    }

    func readCapabilities() async -> String? {
        guard let display = active else { return nil }
        return try? await controller.readCapabilities(display: display.id)
    }

    func apply(profile: Profile) async {
        guard let display = active else {
            banner = DDCError.notConnected.localizedDescription
            return
        }
        for assignment in ProfilePlan.ordered(profile.assignments) {
            do {
                try await controller.writeNow(display: display.id, code: assignment.code, value: assignment.value)
            } catch {
                banner = "\(profile.name) stopped at \(VCPText.formatCode(assignment.code)): \(error.localizedDescription)"
                await readCurrentValues(for: display.id)
                return
            }
        }
        banner = "Applied \(profile.name)."
        await readCurrentValues(for: display.id)
    }

    func profileFromCurrent(named name: String) -> Profile {
        Profile(
            id: UUID(),
            name: name,
            symbol: "square.stack",
            detail: "Captured from the sliders. Values are whatever the connection reported, not a factory calibration.",
            assignments: [
                VCPAssignment(code: MCCSCatalog.Code.colorPreset, value: colorPreset),
                VCPAssignment(code: MCCSCatalog.Code.gainRed, value: red.raw),
                VCPAssignment(code: MCCSCatalog.Code.gainGreen, value: green.raw),
                VCPAssignment(code: MCCSCatalog.Code.gainBlue, value: blue.raw),
                VCPAssignment(code: MCCSCatalog.Code.contrast, value: contrast.raw),
                VCPAssignment(code: MCCSCatalog.Code.brightness, value: brightness.raw),
                VCPAssignment(code: MCCSCatalog.Code.volume, value: volume.raw)
            ]
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemController.setEnabled(enabled)
            settings.launchAtLogin = LoginItemController.isEnabled
            banner = LoginItemController.statusDescription
        } catch {
            settings.launchAtLogin = LoginItemController.isEnabled
            banner = error.localizedDescription
        }
        save()
    }

    func updateTiming() {
        let interval = TimingLimits.intervalMilliseconds(settings.writeMinIntervalMilliseconds)
        let attempts = TimingLimits.attempts(settings.retryAttempts)
        settings.writeMinIntervalMilliseconds = interval
        settings.retryAttempts = attempts
        save()
        Task {
            await controller.setTiming(minIntervalNanoseconds: UInt64(interval) * 1_000_000, retryAttempts: attempts)
        }
    }

    func save() {
        do {
            try store.save(settings)
        } catch {
            banner = "Could not save settings: \(error.localizedDescription)"
        }
    }

    func installHotkeys() {
        hotkeys.update(bindings: settings.hotkeys) { action in
            Task { @MainActor in
                let model = AppModel.shared
                switch action {
                case .brightnessUp: model.stepBrightness(by: Int(model.settings.brightnessStep))
                case .brightnessDown: model.stepBrightness(by: -Int(model.settings.brightnessStep))
                case .volumeUp: model.stepVolume(by: Int(model.settings.volumeStep))
                case .volumeDown: model.stepVolume(by: -Int(model.settings.volumeStep))
                case .toggleMute: model.toggleMute()
                }
            }
        }
    }

    func installMediaKeys() {
        mediaKeys?.stop()
        mediaKeys = nil
        mediaKeysActive = false
        guard settings.mapMediaKeys else { return }
        let monitor = MediaKeyMonitor { key in
            Task { @MainActor in
                let model = AppModel.shared
                switch key {
                case .brightnessUp: model.stepBrightness(by: Int(model.settings.brightnessStep))
                case .brightnessDown: model.stepBrightness(by: -Int(model.settings.brightnessStep))
                case .volumeUp: model.stepVolume(by: Int(model.settings.volumeStep))
                case .volumeDown: model.stepVolume(by: -Int(model.settings.volumeStep))
                case .mute: model.toggleMute()
                }
            }
        }
        mediaKeys = monitor
        mediaKeysActive = monitor.start()
        if !mediaKeysActive {
            banner = "Accessibility permission is required before the brightness and volume keys can control the monitor."
        }
    }

    func setMediaKeys(_ enabled: Bool) {
        settings.mapMediaKeys = enabled
        save()
        if enabled && !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }
        installMediaKeys()
    }

    func assignInput(id: String, value: UInt16?, verified: Bool, note: String? = nil) {
        guard let index = settings.inputBindings.firstIndex(where: { $0.id == id }) else { return }
        settings.inputBindings[index].value = value
        settings.inputBindings[index].verifiedOnThisModel = verified
        if let note { settings.inputBindings[index].note = note }
        save()
    }

    func storeProbe(_ report: ProbeReport) {
        settings.lastProbe = report
        save()
    }

    func pin(_ control: CustomControl) {
        if let index = settings.customControls.firstIndex(where: { $0.code == control.code }) {
            var kept = control
            kept.id = settings.customControls[index].id
            settings.customControls[index] = kept
        } else {
            settings.customControls.append(control)
        }
        save()
    }

    func removeCustom(_ control: CustomControl) {
        settings.customControls.removeAll { $0.id == control.id }
        save()
    }

    func applyScheduleIfNeeded() async {
        guard let display = active else { return }
        guard BrightnessSchedule.shouldApply(
            now: Date(),
            lastManualChange: lastManualBrightness,
            holdoff: settings.scheduleHoldoffSeconds
        ) else { return }
        guard let target = BrightnessSchedule.brightness(
            at: Date(),
            mode: settings.scheduleMode,
            points: settings.schedulePoints,
            solar: settings.solar,
            timeZone: .current
        ) else { return }
        let raw = VCPMapping.raw(percent: Double(target), reportedMaximum: brightness.reportedMax)
        guard raw != brightness.raw else { return }
        do {
            try await controller.writeNow(display: display.id, code: MCCSCatalog.Code.brightness, value: raw)
            brightness.raw = raw
            brightness.percent = Double(target)
        } catch {
            banner = error.localizedDescription
        }
    }

    private func readCurrentValues(for display: DisplayID) async {
        await readSlider(.brightness, display: display, code: MCCSCatalog.Code.brightness)
        await readSlider(.contrast, display: display, code: MCCSCatalog.Code.contrast)
        await readSlider(.volume, display: display, code: MCCSCatalog.Code.volume)
        await readSlider(.red, display: display, code: MCCSCatalog.Code.gainRed)
        await readSlider(.green, display: display, code: MCCSCatalog.Code.gainGreen)
        await readSlider(.blue, display: display, code: MCCSCatalog.Code.gainBlue)
        if let preset = try? await controller.read(display: display, code: MCCSCatalog.Code.colorPreset, attempts: 1) {
            colorPreset = preset.current
        }
        if let mute = try? await controller.read(display: display, code: MCCSCatalog.Code.mute, attempts: 1) {
            muted = MuteMapping.isMuted(current: mute.current)
        }
        for control in settings.customControls {
            if let value = try? await controller.read(display: display, code: control.code, attempts: 1) {
                customValues[control.code] = value.current
            }
        }
    }

    private func readSlider(_ id: SliderID, display: DisplayID, code: UInt8) async {
        do {
            let value = try await controller.read(display: display, code: code, attempts: 1)
            var state = slider(id)
            state.reportedMax = value.maximum
            state.raw = value.current
            state.percent = Double(VCPMapping.percent(raw: value.current, reportedMaximum: value.maximum))
            setSlider(id, state)
        } catch {
            if id == .brightness {
                banner = error.localizedDescription
            }
        }
    }

    private func handle(_ event: DDCControllerEvent) {
        if case .writeFailed(_, let code, let message) = event {
            banner = "VCP \(VCPText.formatCode(code)): \(message)"
        }
    }

    func slider(_ id: SliderID) -> SliderState {
        switch id {
        case .brightness: return brightness
        case .contrast: return contrast
        case .volume: return volume
        case .red: return red
        case .green: return green
        case .blue: return blue
        }
    }

    private func setSlider(_ id: SliderID, _ state: SliderState) {
        switch id {
        case .brightness: brightness = state
        case .contrast: contrast = state
        case .volume: volume = state
        case .red: red = state
        case .green: green = state
        case .blue: blue = state
        }
    }

    private func vcpCode(_ id: SliderID) -> UInt8 {
        switch id {
        case .brightness: return MCCSCatalog.Code.brightness
        case .contrast: return MCCSCatalog.Code.contrast
        case .volume: return MCCSCatalog.Code.volume
        case .red: return MCCSCatalog.Code.gainRed
        case .green: return MCCSCatalog.Code.gainGreen
        case .blue: return MCCSCatalog.Code.gainBlue
        }
    }
}
