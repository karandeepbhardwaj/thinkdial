import SwiftUI
import ThinkDialCore

struct PopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.isRefreshing && model.displays.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for displays…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if model.active == nil {
                        emptyState
                    } else {
                        controls
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 640)
            Divider()
            footer
        }
        .frame(width: 360)
        .task { await model.start() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "dial.medium")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.active?.name ?? "ThinkDial")
                    .font(.headline)
                    .lineLimit(1)
                Text(model.active?.transport.isEmpty == false ? model.active!.transport : "No display selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.demoMode {
                Text("Demo")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.banner ?? "No DDC display found.")
                .font(.callout)
            Text("Enable DDC/CI in the monitor OSD if commands fail, and connect with USB-C or DisplayPort. HDMI on M1 Macs often cannot carry DDC.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Refresh") { Task { await model.refresh() } }
                Button("Use demo mode") { Task { await model.setDemoMode(true) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.demoMode {
                Text("Demo mode is a simulated P34WD-40. Nothing here was read from a real monitor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let banner = model.banner, !model.demoMode || !banner.isEmpty {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.displays.filter({ !$0.isBuiltIn }).count > 1 {
                Picker("Display", selection: displaySelection) {
                    Text("Automatic").tag(Optional<String>.none)
                    ForEach(model.displays) { display in
                        Text(display.name).tag(Optional(display.id.raw))
                    }
                }
                .labelsHidden()
            }

            PercentSlider(title: "Brightness", systemImage: "sun.max", state: model.brightness) {
                model.commitSlider(.brightness, percent: $0)
            }
            PercentSlider(title: "Contrast", systemImage: "circle.lefthalf.filled", state: model.contrast) {
                model.commitSlider(.contrast, percent: $0)
            }
            HStack(alignment: .center, spacing: 8) {
                PercentSlider(title: "Volume", systemImage: model.muted == true ? "speaker.slash" : "speaker.wave.2", state: model.volume) {
                    model.commitSlider(.volume, percent: $0)
                }
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .help(model.muted == nil ? "Mute state was not 0x01 or 0x02. Click to write the MCCS mute values." : "Mute")
            }

            Picker("Colour", selection: presetSelection) {
                ForEach(model.settings.colorPresets) { preset in
                    Text(preset.label).tag(preset.value)
                }
            }
            Text("VCP 0x14 names are from MCCS. This panel may only accept some of them.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            DisclosureGroup("Red, green, blue gain") {
                VStack(alignment: .leading, spacing: 10) {
                    PercentSlider(title: "Red", systemImage: "circle.fill", state: model.red) {
                        model.commitSlider(.red, percent: $0)
                    }
                    PercentSlider(title: "Green", systemImage: "circle.fill", state: model.green) {
                        model.commitSlider(.green, percent: $0)
                    }
                    PercentSlider(title: "Blue", systemImage: "circle.fill", state: model.blue) {
                        model.commitSlider(.blue, percent: $0)
                    }
                }
                .padding(.top, 6)
            }
            .font(.subheadline.weight(.medium))

            inputRow
            if !model.settings.customControls.isEmpty {
                customControls
            }
            profileRow
            powerButton
        }
    }

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Input")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(model.settings.inputBindings) { binding in
                    Button(inputTitle(binding)) {
                        pendingInput = binding
                    }
                    .buttonStyle(.bordered)
                    .disabled(binding.value == nil)
                    .frame(maxWidth: .infinity)
                }
            }
            Text("DisplayPort starts at MCCS 0x0F and HDMI at 0x11. USB-C has no default. None of these are confirmed on the P34WD-40.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned")
                .font(.subheadline.weight(.medium))
            ForEach(model.settings.customControls) { control in
                CustomControlRow(control: control, value: model.customValues[control.code] ?? control.minimum) { newValue in
                    model.commitCustom(code: control.code, value: newValue)
                }
            }
        }
    }

    private var profileRow: some View {
        HStack {
            Menu {
                ForEach(model.settings.profiles) { profile in
                    Button {
                        Task { await model.apply(profile: profile) }
                    } label: {
                        Label(profile.name, systemImage: profile.symbol)
                    }
                }
            } label: {
                Label("Profile", systemImage: "square.stack")
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
    }

    private var powerButton: some View {
        Button {
            powerConfirm = true
        } label: {
            Label("Turn display off", systemImage: "power")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .alert("Switch input?", isPresented: inputAlertPresented) {
            Button("Switch", role: .destructive) {
                if let pendingInput { Task { await switchInput(pendingInput) } }
            }
            Button("Cancel", role: .cancel) { pendingInput = nil }
        } message: {
            Text(InputCandidateCatalog.disconnectWarning)
        }
        .alert("Turn the display off?", isPresented: $powerConfirm) {
            Button("Turn off", role: .destructive) {
                Task {
                    try? await model.writeNow(code: PowerMapping.code, value: PowerMapping.off)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This writes VCP 0xD6 = 0x05, the MCCS “turn off” value. It is not confirmed on the P34WD-40, and DDC often cannot wake the panel afterwards.")
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            footerButton("Probe", "waveform.path.ecg", "probe")
            footerButton("Profiles", "square.stack.3d.up", "profiles")
            footerButton("Inputs", "arrow.left.arrow.right", "inputs")
            Spacer()
            Button {
                model.settingsPage = .general
                activate()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func footerButton(_ title: String, _ symbol: String, _ window: String) -> some View {
        Button {
            activate()
            openWindow(id: window)
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private var displaySelection: Binding<String?> {
        Binding(
            get: { model.settings.selectedDisplayID },
            set: { newValue in
                Task {
                    if let newValue, let display = model.displays.first(where: { $0.id.raw == newValue }) {
                        await model.select(display: display)
                    } else {
                        await model.useAutomaticDisplay()
                    }
                }
            }
        )
    }

    private var presetSelection: Binding<UInt16> {
        Binding(get: { model.colorPreset }, set: { model.commitPreset($0) })
    }

    @State private var powerConfirm = false
    @State private var pendingInput: InputBinding?

    private var inputAlertPresented: Binding<Bool> {
        Binding(get: { pendingInput != nil }, set: { if !$0 { pendingInput = nil } })
    }

    private func inputTitle(_ binding: InputBinding) -> String {
        if let value = binding.value {
            return "\(binding.title) \(VCPText.format(value))"
        }
        return "\(binding.title) —"
    }

    private func switchInput(_ binding: InputBinding) async {
        guard let value = binding.value else { return }
        try? await model.writeNow(code: MCCSCatalog.Code.inputSource, value: value)
    }

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct PercentSlider: View {
    let title: String
    let systemImage: String
    let state: SliderState
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(state.percent.rounded()))")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 36, alignment: .trailing)
            }
            Slider(
                value: Binding(get: { state.percent }, set: onChange),
                in: 0...100
            )
            .accessibilityLabel(title)
            Text("Raw \(state.raw) of \(state.reportedMax)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct CustomControlRow: View {
    let control: CustomControl
    let value: UInt16
    let onChange: (UInt16) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.label)
                Spacer()
                Text(VCPText.formatCode(control.code))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            switch control.kind {
            case .slider:
                let upper = max(Int(control.minimum) + 1, Int(control.maximum))
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { onChange(UInt16(min(Double(upper), max(Double(control.minimum), $0)).rounded())) }
                    ),
                    in: Double(control.minimum)...Double(upper)
                )
            case .toggle:
                Toggle(control.label, isOn: Binding(
                    get: { value == control.toggleOn },
                    set: { onChange($0 ? control.toggleOn : control.toggleOff) }
                ))
                .labelsHidden()
            case .picker:
                Picker(control.label, selection: Binding(get: { value }, set: onChange)) {
                    ForEach(control.choices) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .labelsHidden()
            }
        }
    }
}
