import SwiftUI
import ThinkDialCore
import UniformTypeIdentifiers

struct ProbeView: View {
    @ObservedObject var model: AppModel
    @State private var capabilities = ""
    @State private var readings: [ProbeReading] = []
    @State private var labels: [UInt8: String] = [:]
    @State private var scanning = false
    @State private var progress: Double = 0
    @State private var status = "Reads only, until you arm writes."
    @State private var armed = false
    @State private var armConfirm = false
    @State private var pendingWrite: (code: UInt8, value: UInt16)?
    @State private var writeCode = "0x10"
    @State private var writeValue = "0"
    @State private var showSilent = false
    @State private var exportDocument: JSONDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ProbeReport.disclaimer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Read capabilities") { Task { await readCapabilities() } }
                        .disabled(scanning)
                    Button(scanning ? "Stop scan" : "Scan 0x00–0xFF") { toggleScan() }
                    Button("Export JSON") { export() }
                        .disabled(readings.isEmpty && capabilities.isEmpty)
                    Button("Import JSON") { importing = true }
                    Toggle("Show silent codes", isOn: $showSilent)
                        .disabled(readings.isEmpty)
                    Spacer()
                    Toggle("Arm writes", isOn: armBinding)
                        .toggleStyle(.switch)
                }
                if scanning {
                    ProgressView(value: progress) {
                        Text(String(format: "Scanning… %d%%", Int(progress * 100)))
                            .font(.caption)
                    }
                } else {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            if !capabilities.isEmpty {
                Text(capabilities)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            List {
                ForEach(visibleRows) { row in
                    ProbeRowView(row: row, label: labels[row.code] ?? row.label) { newLabel in
                        labels[row.code] = newLabel
                    } onPin: { kind in
                        let labeled = ProbeRow(
                            code: row.code,
                            inCapabilities: row.inCapabilities,
                            capabilityValues: row.capabilityValues,
                            responded: row.responded,
                            current: row.current,
                            maximum: row.maximum,
                            mccsName: row.mccsName,
                            label: labels[row.code] ?? row.label
                        )
                        model.pin(CustomControl.pinned(from: labeled, kind: kind, label: labels[row.code] ?? ""))
                        status = "Pinned \(VCPText.formatCode(row.code)) on the menu."
                    }
                }
            }

            if armed {
                HStack {
                    TextField("Code", text: $writeCode).frame(width: 80)
                    TextField("Value", text: $writeValue).frame(width: 80)
                    Button("Send value…") { stageWrite() }
                    Text("Sends a Set VCP. Confirm on the next alert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear(perform: loadLast)
        .alert("Allow probe writes?", isPresented: $armConfirm) {
            Button("Arm writes") { armed = true }
            Button("Cancel", role: .cancel) { armed = false }
        } message: {
            Text(ProbeWritePolicy.armingWarning)
        }
        .alert("Send this value?", isPresented: writeAlert) {
            Button("Send", role: .destructive) { Task { await sendPending() } }
            Button("Cancel", role: .cancel) { pendingWrite = nil }
        } message: {
            Text(pendingWrite.map { "Set VCP \(VCPText.formatCode($0.code)) to \(VCPText.format($0.value))." } ?? "")
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "thinkdial-probe") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                importReport(data)
            }
        }
    }

    private var visibleRows: [ProbeRow] {
        let parsed = capabilities.isEmpty ? nil : CapabilitiesParser.parse(capabilities)
        if showSilent {
            return readings.map { reading in
                ProbeRow(
                    code: reading.code,
                    inCapabilities: parsed?.feature(reading.code) != nil,
                    capabilityValues: parsed?.feature(reading.code)?.values ?? [],
                    responded: reading.responded,
                    current: reading.current,
                    maximum: reading.maximum,
                    mccsName: MCCSCatalog.name(for: reading.code),
                    label: labels[reading.code] ?? ""
                )
            }
        }
        return ProbeMerge.rows(capabilities: parsed, readings: readings, labels: labels)
    }

    private var armBinding: Binding<Bool> {
        Binding(get: { armed }, set: { newValue in
            if newValue { armConfirm = true } else { armed = false }
        })
    }

    private var writeAlert: Binding<Bool> {
        Binding(get: { pendingWrite != nil }, set: { if !$0 { pendingWrite = nil } })
    }

    private func loadLast() {
        guard let report = model.settings.lastProbe else { return }
        capabilities = report.capabilitiesRaw ?? ""
        readings = report.readings
        labels = report.labelMap
        status = "Showing the saved probe from \(report.capturedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private func readCapabilities() async {
        status = "Asking for the capabilities string…"
        if let text = await model.readCapabilities() {
            capabilities = text
            status = "Capabilities string received. It is not a published Lenovo list."
        } else {
            status = "No capabilities string. AppleSiliconDDC only exposes get and set VCP, so discovery on Apple Silicon is the scan below. An Intel Mac also tries a framebuffer I2C read."
        }
        persist()
    }

    private func toggleScan() {
        if scanning {
            scanTask?.cancel()
            scanning = false
            status = "Scan stopped."
            persist()
            return
        }
        scanning = true
        progress = 0
        readings = []
        scanTask = Task {
            var collected: [ProbeReading] = []
            for value in 0...255 {
                if Task.isCancelled { break }
                let code = UInt8(value)
                let result: Result<VCPValue, Error>
                do { result = .success(try await model.readCode(code)) }
                catch { result = .failure(error) }
                let reading = ProbeInterpreter.reading(code: code, result: result)
                collected.append(reading)
                readings = collected
                progress = Double(value) / 255
            }
            scanning = false
            let hits = collected.filter(\.responded).count
            status = "\(hits) codes responded."
            persist()
        }
    }

    private func stageWrite() {
        guard let codeValue = VCPText.parse(writeCode, max: 0xFF),
              let code = UInt8(exactly: codeValue),
              let value = VCPText.parse(writeValue) else {
            status = "Enter a code (0x00–0xFF) and a value."
            return
        }
        guard armed else {
            status = "Arm writes and confirm the alert before sending."
            return
        }
        pendingWrite = (code, value)
    }

    private func sendPending() async {
        guard let pendingWrite, ProbeWritePolicy.allows(armed: armed, confirmedThisWrite: true) else { return }
        do {
            try await model.writeNow(code: pendingWrite.code, value: pendingWrite.value)
            status = "Wrote \(VCPText.formatCode(pendingWrite.code))."
        } catch {
            status = error.localizedDescription
        }
        self.pendingWrite = nil
    }

    private func persist() {
        guard let display = model.active else { return }
        let report = ProbeReport(
            displayName: display.name,
            displayID: display.id.raw,
            capturedAt: Date(),
            capabilitiesRaw: capabilities.isEmpty ? nil : capabilities,
            readings: readings,
            labels: labels.map { CodeLabel(code: $0.key, label: $0.value) }.sorted { $0.code < $1.code },
            pinnedControls: model.settings.customControls
        )
        model.storeProbe(report)
    }

    private func export() {
        guard let display = model.active else { return }
        let report = ProbeReport(
            displayName: display.name,
            displayID: display.id.raw,
            capturedAt: Date(),
            capabilitiesRaw: capabilities.isEmpty ? nil : capabilities,
            readings: readings,
            labels: labels.map { CodeLabel(code: $0.key, label: $0.value) }.sorted { $0.code < $1.code },
            pinnedControls: model.settings.customControls
        )
        if let data = try? ProbeExport.encode(report) {
            exportDocument = JSONDocument(data: data)
            exporting = true
        }
    }

    private func importReport(_ data: Data) {
        do {
            let report = try ProbeExport.decode(data)
            capabilities = report.capabilitiesRaw ?? ""
            readings = report.readings
            labels = report.labelMap
            model.settings.customControls = ProbeLibrary.mergePins(existing: model.settings.customControls, imported: report.pinnedControls)
            model.storeProbe(report)
            status = "Imported probe for \(report.displayName)."
        } catch {
            status = error.localizedDescription
        }
    }
}

private struct ProbeRowView: View {
    let row: ProbeRow
    let label: String
    let onLabel: (String) -> Void
    let onPin: (ControlKind) -> Void
    @State private var draft: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(VCPText.formatCode(row.code))
                .font(.body.monospaced())
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.mccsName ?? "No MCCS name")
                    .font(.callout)
                HStack(spacing: 8) {
                    if row.responded {
                        Text("current \(row.current.map(String.init) ?? "—") · max \(row.maximum.map(String.init) ?? "—")")
                    } else {
                        Text("no getvcp reply")
                    }
                    if row.inCapabilities { Text("in capabilities") }
                    if !row.capabilityValues.isEmpty {
                        Text(row.capabilityValues.map { VCPText.format(UInt16($0)) }.joined(separator: " "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Label", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .onSubmit { onLabel(draft) }
            Menu("Pin") {
                Button("Slider") { onLabel(draft); onPin(.slider) }
                Button("Toggle") { onLabel(draft); onPin(.toggle) }
                Button("Picker") { onLabel(draft); onPin(.picker) }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 64)
        }
        .onAppear { draft = label }
    }
}
