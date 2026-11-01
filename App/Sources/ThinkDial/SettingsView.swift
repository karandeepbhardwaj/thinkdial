import AppKit
import SwiftUI
import ThinkDialCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsPage) {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPage.general)
            InputSettings(model: model)
                .tabItem { Label("Inputs", systemImage: "arrow.left.arrow.right") }
                .tag(SettingsPage.inputs)
            ColorSettings(model: model)
                .tabItem { Label("Colour", systemImage: "paintpalette") }
                .tag(SettingsPage.color)
            HotkeySettings(model: model)
                .tabItem { Label("Keys", systemImage: "keyboard") }
                .tag(SettingsPage.hotkeys)
            ScheduleSettings(model: model)
                .tabItem { Label("Schedule", systemImage: "clock") }
                .tag(SettingsPage.schedule)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsPage.about)
        }
        .frame(width: 680, height: 520)
        .padding(12)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("Demo mode", isOn: Binding(
                get: { model.demoMode },
                set: { enabled in Task { await model.setDemoMode(enabled) } }
            ))
            Text("Demo mode uses a simulated ThinkVision so you can try the menus without a monitor. The simulated capabilities string is labeled SIMULATED.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Open at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Text(LoginItemController.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Display", selection: Binding(
                get: { model.settings.selectedDisplayID ?? "" },
                set: { value in
                    Task {
                        if value.isEmpty {
                            await model.useAutomaticDisplay()
                        } else if let display = model.displays.first(where: { $0.id.raw == value }) {
                            await model.select(display: display)
                        }
                    }
                }
            )) {
                Text("Automatic (Lenovo P34WD if present)").tag("")
                ForEach(model.displays) { display in
                    Text(display.name).tag(display.id.raw)
                }
            }

            Stepper(value: Binding(
                get: { model.settings.writeMinIntervalMilliseconds },
                set: {
                    model.settings.writeMinIntervalMilliseconds = $0
                    model.updateTiming()
                }
            ), in: 20...5_000, step: 10) {
                Text("Minimum gap between writes: \(model.settings.writeMinIntervalMilliseconds) ms")
            }
            Stepper(value: Binding(
                get: { model.settings.retryAttempts },
                set: {
                    model.settings.retryAttempts = $0
                    model.updateTiming()
                }
            ), in: 1...6) {
                Text("Retries after a failed read or write: \(model.settings.retryAttempts)")
            }
            Button("Refresh displays") { Task { await model.refresh() } }
        }
        .formStyle(.grouped)
    }
}

private struct InputSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Text("Defaults are starting points, not facts about the P34WD-40. USB-C is blank until you set it. Use the input tester before trusting a number.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach($model.settings.inputBindings) { $binding in
                Section(binding.title) {
                    TextField("Value (hex or decimal, blank to clear)", text: Binding(
                        get: { binding.value.map(VCPText.format) ?? "" },
                        set: { text in
                            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                                binding.value = nil
                            } else if let parsed = VCPText.parse(text) {
                                binding.value = parsed
                                binding.verifiedOnThisModel = false
                            }
                        }
                    ))
                    Text(binding.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("I have confirmed this value on this monitor", isOn: $binding.verifiedOnThisModel)
                }
            }
            Button("Save input values") { model.save() }
        }
        .formStyle(.grouped)
    }
}

private struct ColorSettings: View {
    @ObservedObject var model: AppModel
    @State private var label = "Custom"
    @State private var value = "0x0B"

    var body: some View {
        Form {
            Text("These are MCCS names for VCP 0x14. Delete the ones this panel rejects after you probe it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.settings.colorPresets) { preset in
                HStack {
                    Text("\(preset.label) · \(VCPText.format(preset.value))")
                    Spacer()
                    Button("Remove") {
                        model.settings.colorPresets.removeAll { $0.value == preset.value }
                        model.save()
                    }
                }
            }
            HStack {
                TextField("Label", text: $label)
                TextField("Value", text: $value)
                    .frame(width: 80)
                Button("Add") {
                    guard let parsed = VCPText.parse(value), !model.settings.colorPresets.contains(where: { $0.value == parsed }) else { return }
                    model.settings.colorPresets.append(LabeledValue(value: parsed, label: label, note: "Added in settings. Not confirmed on the P34WD-40."))
                    model.save()
                }
            }
            Button("Restore MCCS names") {
                model.settings.colorPresets = ColorPresets.mccsDefaults()
                model.save()
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotkeySettings: View {
    @ObservedObject var model: AppModel
    @State private var recording: HotkeyAction?
    @State private var monitor: Any?

    var body: some View {
        Form {
            Toggle("Brightness and volume keys control the ThinkVision", isOn: Binding(
                get: { model.settings.mapMediaKeys },
                set: { model.setMediaKeys($0) }
            ))
            Text(model.mediaKeysActive
                 ? "Those keys are going to the monitor. The built-in display will not see them."
                 : "Off by default. Turning this on needs Accessibility permission, because macOS hides these keys from ordinary apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.settings.mapMediaKeys && !model.mediaKeysActive {
                Button("Allow Accessibility") { AccessibilityPermission.prompt() }
            }
            Stepper(value: Binding(
                get: { Int(model.settings.brightnessStep) },
                set: { model.settings.brightnessStep = UInt16($0); model.save() }
            ), in: 1...25) {
                Text("Brightness step: \(model.settings.brightnessStep)")
            }
            Stepper(value: Binding(
                get: { Int(model.settings.volumeStep) },
                set: { model.settings.volumeStep = UInt16($0); model.save() }
            ), in: 1...25) {
                Text("Volume step: \(model.settings.volumeStep)")
            }

            ForEach(HotkeyAction.allCases) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    Text(bindingText(action))
                        .foregroundStyle(.secondary)
                    Button(recording == action ? "Press keys…" : "Record") {
                        beginRecording(action)
                    }
                    Button("Clear") {
                        model.settings.hotkeys.removeAll { $0.action == action }
                        model.save()
                        model.installHotkeys()
                    }
                }
            }
            Text("Shortcuts need at least one modifier. Escape cancels recording. They are not swallowed, so pick a combination macOS is not already using.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func bindingText(_ action: HotkeyAction) -> String {
        guard let binding = model.settings.hotkeys.first(where: { $0.action == action }) else { return "None" }
        return binding.modifiers.symbols + KeyCodeName.name(for: binding.keyCode)
    }

    private func beginRecording(_ action: HotkeyAction) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    recording = nil
                    if let monitor { NSEvent.removeMonitor(monitor) }
                    self.monitor = nil
                }
                return nil
            }
            let modifiers = KeyCodeName.modifiers(from: event.modifierFlags)
            guard !modifiers.isEmpty else { return event }
            let binding = HotkeyBinding(action: action, keyCode: event.keyCode, modifiers: modifiers)
            DispatchQueue.main.async {
                model.settings.hotkeys.removeAll { $0.action == action }
                model.settings.hotkeys.append(binding)
                model.save()
                model.installHotkeys()
                recording = nil
                if let monitor { NSEvent.removeMonitor(monitor) }
                self.monitor = nil
            }
            return nil
        }
    }
}

private struct ScheduleSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Picker("Brightness schedule", selection: $model.settings.scheduleMode) {
                Text("Off").tag(ScheduleMode.off)
                Text("Time of day").tag(ScheduleMode.clock)
                Text("Sunrise and sunset").tag(ScheduleMode.solar)
            }
            .onChange(of: model.settings.scheduleMode) { _ in model.save() }

            Text("After you move the brightness slider, the schedule waits \(Int(model.settings.scheduleHoldoffSeconds)) seconds before it takes over again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.settings.scheduleMode == .clock {
                ForEach(model.settings.schedulePoints.indices, id: \.self) { index in
                    HStack {
                        Text(clockLabel(model.settings.schedulePoints[index].minutesFromMidnight))
                        Stepper("Brightness \(model.settings.schedulePoints[index].brightness)", value: Binding(
                            get: { Int(model.settings.schedulePoints[index].brightness) },
                            set: {
                                model.settings.schedulePoints[index].brightness = UInt16($0)
                                model.save()
                            }
                        ), in: 0...100)
                        Button(role: .destructive) {
                            model.settings.schedulePoints.remove(at: index)
                            model.save()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add point at noon") {
                    model.settings.schedulePoints.append(SchedulePoint(minutesFromMidnight: 12 * 60, brightness: 60))
                    model.save()
                }
            }

            if model.settings.scheduleMode == .solar {
                TextField("Latitude", text: coordinate(\.latitude))
                TextField("Longitude", text: coordinate(\.longitude))
                Text("Coordinates are typed. ThinkDial does not request location access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Day \(model.settings.solar.dayBrightness)", value: Binding(
                    get: { Int(model.settings.solar.dayBrightness) },
                    set: { model.settings.solar.dayBrightness = UInt16($0); model.save() }
                ), in: 0...100)
                Stepper("Night \(model.settings.solar.nightBrightness)", value: Binding(
                    get: { Int(model.settings.solar.nightBrightness) },
                    set: { model.settings.solar.nightBrightness = UInt16($0); model.save() }
                ), in: 0...100)
                Stepper("Fade \(model.settings.solar.transitionMinutes) min", value: Binding(
                    get: { model.settings.solar.transitionMinutes },
                    set: { model.settings.solar.transitionMinutes = $0; model.save() }
                ), in: 0...180)
            }
        }
        .formStyle(.grouped)
    }

    private func clockLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func coordinate(_ keyPath: WritableKeyPath<SolarSchedule, Double?>) -> Binding<String> {
        Binding(
            get: { model.settings.solar[keyPath: keyPath].map { String($0) } ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                model.settings.solar[keyPath: keyPath] = trimmed.isEmpty ? nil : Double(trimmed)
                model.save()
            }
        )
    }
}

private struct AboutSettings: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("ThinkDial")
                    .font(.title2.weight(.semibold))
                Text("A menu-bar stand-in for the ThinkVision P34WD-40’s on-screen menu. DDC on Apple Silicon goes through AppleSiliconDDC. Intel Macs use a best-effort I2C fallback.")
                Text("KVM, picture-by-picture, and True Split are not mapped. If the probe finds a vendor code and you can tell what it does, pin it. ThinkDial will not guess those features.")
                Text("No P34WD-40 capability string or input-source table is published, so those values stay editable and are labeled as unverified.")
                Text("AppleSiliconDDC © waydabber, MIT. The Intel transaction shape is informed by MonitorControl, MIT. ThinkDial itself is MIT.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
