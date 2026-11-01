import SwiftUI
import ThinkDialCore

struct InputTesterView: View {
    @ObservedObject var model: AppModel
    @State private var pending: UInt16?
    @State private var custom = "0x0F"
    @State private var assignTarget = InputBinding.usbC
    @State private var markVerified = false
    @State private var status = "Pick a candidate. Nothing is sent until you confirm."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(InputCandidateCatalog.disconnectWarning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("These numbers are candidates, not a map of the P34WD-40. USB-C in particular has no MCCS value. Dell has used 0x1B, and an older Lenovo P44w-10 has been reported with 0x13 and 0x14.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(InputCandidateCatalog.all) { candidate in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(candidate.label) · \(VCPText.format(candidate.value))")
                            .font(.headline)
                        Text(candidate.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Test…") { pending = candidate.value }
                }
                .padding(.vertical, 4)
            }

            HStack {
                TextField("Other value", text: $custom)
                    .frame(width: 100)
                Button("Test other value…") {
                    if let value = VCPText.parse(custom) { pending = value }
                    else { status = "Could not parse that value." }
                }
            }

            Divider()
            Text(status).font(.callout)
            HStack {
                Picker("If it worked, save as", selection: $assignTarget) {
                    ForEach(model.settings.inputBindings) { binding in
                        Text(binding.title).tag(binding.id)
                    }
                }
                Toggle("I confirmed this on my monitor", isOn: $markVerified)
                Button("Save last tested value") { saveLast() }
                    .disabled(pending != nil)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
        .alert("Send input value?", isPresented: alertPresented) {
            Button("Send", role: .destructive) { Task { await send() } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(pending.map { value in
                "This writes VCP 0x60 = \(VCPText.format(value)). \(InputCandidateCatalog.disconnectWarning)"
            } ?? "")
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func send() async {
        guard let value = pending, InputSwitchPolicy.allows(confirmed: true) else { return }
        pending = nil
        do {
            try await model.writeNow(code: MCCSCatalog.Code.inputSource, value: value)
            status = "Sent \(VCPText.format(value)). If the picture went away, switch the input back on the monitor, then save the value if it was the one you wanted."
            custom = VCPText.format(value)
        } catch {
            status = error.localizedDescription
        }
    }

    private func saveLast() {
        guard let value = VCPText.parse(custom) else { return }
        let note = markVerified
            ? "Confirmed in the input tester on this monitor."
            : "Saved from the input tester. Not marked as confirmed."
        model.assignInput(id: assignTarget, value: value, verified: markVerified, note: note)
        status = "Saved \(VCPText.format(value)) on \(assignTarget)."
    }
}
