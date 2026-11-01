import SwiftUI
import ThinkDialCore

struct ProfilesView: View {
    @ObservedObject var model: AppModel
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.settings.profiles) { profile in
                    Label(profile.name, systemImage: profile.symbol)
                        .tag(profile.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                Button {
                    let profile = model.profileFromCurrent(named: "Captured")
                    model.settings.profiles.append(profile)
                    model.save()
                    selection = profile.id
                } label: {
                    Label("Capture current", systemImage: "plus")
                }
                Button("Restore built-ins") {
                    for profile in Profile.builtins() where !model.settings.profiles.contains(where: { $0.id == profile.id }) {
                        model.settings.profiles.append(profile)
                    }
                    model.save()
                }
            }
        } detail: {
            if let binding = profileBinding {
                ProfileEditor(profile: binding) {
                    if let id = selection {
                        model.settings.profiles.removeAll { $0.id == id }
                        model.save()
                        selection = model.settings.profiles.first?.id
                    }
                } apply: {
                    if let profile = model.settings.profiles.first(where: { $0.id == selection }) {
                        Task { await model.apply(profile: profile) }
                    }
                }
            } else {
                Text("Choose a profile, or capture the sliders into a new one.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if selection == nil { selection = model.settings.profiles.first?.id }
        }
    }

    private var profileBinding: Binding<Profile>? {
        guard let selection, let index = model.settings.profiles.firstIndex(where: { $0.id == selection }) else { return nil }
        return Binding(
            get: { model.settings.profiles[index] },
            set: {
                model.settings.profiles[index] = $0
                model.save()
            }
        )
    }
}

private struct ProfileEditor: View {
    @Binding var profile: Profile
    let delete: () -> Void
    let apply: () -> Void

    var body: some View {
        Form {
            TextField("Name", text: $profile.name)
            TextField("Symbol", text: $profile.symbol)
            TextField("Note", text: $profile.detail, axis: .vertical)
                .lineLimit(2...4)
            Section("Values") {
                ForEach(profile.assignments.indices, id: \.self) { index in
                    HStack {
                        TextField("Code", text: codeBinding(index))
                            .frame(width: 80)
                        TextField("Value", text: valueBinding(index))
                            .frame(width: 80)
                        Spacer()
                        Button(role: .destructive) {
                            profile.assignments.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add value") {
                    profile.assignments.append(VCPAssignment(code: 0x10, value: 50))
                }
            }
            HStack {
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                Button("Delete profile", role: .destructive, action: delete)
            }
            Text("Applying sends the values in order, with the last duplicate of a code winning. Put a color preset before brightness if the preset resets brightness.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func codeBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { VCPText.formatCode(profile.assignments[index].code) },
            set: { text in
                if let parsed = VCPText.parse(text, max: 0xFF), let code = UInt8(exactly: parsed) {
                    profile.assignments[index].code = code
                }
            }
        )
    }

    private func valueBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { String(profile.assignments[index].value) },
            set: { text in
                if let parsed = VCPText.parse(text) {
                    profile.assignments[index].value = parsed
                }
            }
        )
    }
}
