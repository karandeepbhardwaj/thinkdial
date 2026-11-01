import Foundation
import ThinkDialCore
import ThinkDialDDCSupport

enum CapabilitiesTransport {
    /// Pages opcode 0xF3. Returns nil when the panel does not answer — expected until a real
    /// P34WD-40 capabilities string has been captured. Call this off the main thread.
    static func readString(service: UnsafeMutableRawPointer?) -> String? {
        guard let service else { return nil }
        var fragments: [CapabilitiesFragment] = []
        var offset = 0
        for _ in 0..<32 {
            guard let fragment = readPage(service: service, offset: offset), !fragment.text.isEmpty else { break }
            fragments.append(fragment)
            let next = fragment.offset + fragment.text.utf8.count
            if next <= offset { break }
            offset = next
        }
        let text = CapabilitiesReply.assemble(fragments).trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
        guard text.contains("vcp") || text.contains("prot") else { return nil }
        return text
    }

    private static func readPage(service: UnsafeMutableRawPointer, offset: Int) -> CapabilitiesFragment? {
        let packet = CapabilitiesRequest.payload(offset: offset)
        let wrote = packet.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 1 }
            return TDWriteI2C(service, 0x37, 0x51, base, UInt32(buffer.count))
        }
        guard wrote == 0 else { return nil }
        Thread.sleep(forTimeInterval: 0.05)
        var reply = [UInt8](repeating: 0, count: 64)
        let read = reply.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 1 }
            return TDReadI2C(service, 0x37, 0x51, base, UInt32(buffer.count))
        }
        guard read == 0 else { return nil }
        return CapabilitiesReply.parse(reply)
    }
}

func thinkDialServicePointer<T: AnyObject>(_ object: T?) -> UnsafeMutableRawPointer? {
    guard let object else { return nil }
    return Unmanaged.passUnretained(object).toOpaque()
}
