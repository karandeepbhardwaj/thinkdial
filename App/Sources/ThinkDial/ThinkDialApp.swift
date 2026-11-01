import AppKit
import SwiftUI
import ThinkDialCore
import UniformTypeIdentifiers

@main
struct ThinkDialApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(systemName: "dial.medium")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }

        Window("VCP probe", id: "probe") {
            ProbeView(model: model)
        }
        .defaultSize(width: 760, height: 640)

        Window("Profiles", id: "profiles") {
            ProfilesView(model: model)
        }
        .defaultSize(width: 720, height: 520)

        Window("Input tester", id: "inputs") {
            InputTesterView(model: model)
        }
        .defaultSize(width: 640, height: 560)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            await AppModel.shared.start()
        }
    }
}

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
