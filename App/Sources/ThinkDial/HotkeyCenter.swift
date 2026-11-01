import AppKit
import ApplicationServices
import Foundation
import ThinkDialCore

enum KeyCodeName {
    static func name(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    static func matches(_ event: NSEvent, binding: HotkeyBinding) -> Bool {
        guard event.keyCode == binding.keyCode else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers(from: flags) == binding.modifiers && !binding.modifiers.isEmpty
    }
}

final class HotkeyCenter {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var bindings: [HotkeyBinding] = []
    private var handler: ((HotkeyAction) -> Void)?

    func update(bindings: [HotkeyBinding], handler: @escaping (HotkeyAction) -> Void) {
        self.bindings = bindings.filter { !$0.modifiers.isEmpty }
        self.handler = handler
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }
    }

    private func handle(_ event: NSEvent) {
        guard let binding = bindings.first(where: { KeyCodeName.matches(event, binding: $0) }) else { return }
        let action = binding.action
        DispatchQueue.main.async { [handler] in
            handler?(action)
        }
    }
}

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
