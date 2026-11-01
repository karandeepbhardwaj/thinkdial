import AppKit
import CoreGraphics
import Foundation

enum MediaKey {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case mute
}

/// Swallows the brightness and volume keys while the user has asked ThinkDial to own them.
/// Requires Accessibility permission. The tap is not installed until that option is turned on.
final class MediaKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: (MediaKey) -> Void

    init(handler: @escaping (MediaKey) -> Void) {
        self.handler = handler
    }

    func start() -> Bool {
        stop()
        guard AccessibilityPermission.isTrusted else { return false }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: thinkDialMediaKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyState = (data & 0xFF00) >> 8
        guard keyState == 0x0A else { return Unmanaged.passUnretained(event) }
        let media: MediaKey?
        switch keyCode {
        case 2: media = .brightnessUp
        case 3: media = .brightnessDown
        case 0: media = .volumeUp
        case 1: media = .volumeDown
        case 7: media = .mute
        default: media = nil
        }
        guard let media else { return Unmanaged.passUnretained(event) }
        DispatchQueue.main.async { [handler] in handler(media) }
        return nil
    }
}

private func thinkDialMediaKeyCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
