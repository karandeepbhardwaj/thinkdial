import Foundation

/// DDC/CI checksums and reply frames.
///
/// AppleSiliconDDC checks a Get VCP reply by XOR-ing seed `0x50` across every byte except the
/// checksum. Host request packets that do not include the 0x6E / 0x51 address bytes use seed
/// `0x6E ^ 0x51` over the length byte and payload. Both are covered by tests. This is the
/// framing used by the library, not a claim about unpublished Lenovo commands.
public enum DDCChecksum {
    public static func xor(seed: UInt8, data: [UInt8]) -> UInt8 {
        data.reduce(seed) { $0 ^ $1 }
    }

    /// Checksum for a packet whose I2C address bytes are passed separately (chip 0x37, data 0x51).
    public static func requestChecksum(payloadIncludingLength: [UInt8]) -> UInt8 {
        xor(seed: 0x6E ^ 0x51, data: payloadIncludingLength)
    }
}

public enum VCPReply {
    /// Parse an 11-byte Get VCP reply in the layout AppleSiliconDDC reads back.
    /// Returns nil when the opcode echo, result code, or checksum does not match.
    public static func parseGet(buffer: [UInt8], expectedCode: UInt8) -> VCPValue? {
        guard buffer.count >= 11 else { return nil }
        guard buffer[0] == 0x6E, buffer[2] == 0x02, buffer[3] == 0x00, buffer[4] == expectedCode else {
            return nil
        }
        let expected = DDCChecksum.xor(seed: 0x50, data: Array(buffer[0..<10]))
        guard buffer[10] == expected else { return nil }
        let maximum = UInt16(buffer[6]) << 8 | UInt16(buffer[7])
        let current = UInt16(buffer[8]) << 8 | UInt16(buffer[9])
        return VCPValue(current: current, maximum: maximum)
    }
}

public struct CapabilitiesFragment: Equatable, Sendable {
    public var offset: Int
    public var text: String

    public init(offset: Int, text: String) {
        self.offset = offset
        self.text = text
    }
}

public enum CapabilitiesRequest {
    /// One page of a DDC/CI capabilities request (opcode 0xF3) at `offset`.
    /// The returned bytes are what IOAVServiceWriteI2C sends after the 0x51 data address.
    public static func payload(offset: Int) -> [UInt8] {
        let bounded = max(0, offset)
        let body: [UInt8] = [0x83, 0xF3, UInt8((bounded >> 8) & 0xFF), UInt8(bounded & 0xFF)]
        return body + [DDCChecksum.requestChecksum(payloadIncludingLength: body)]
    }
}

public enum CapabilitiesReply {
    /// Parse one capabilities-reply frame. `buffer[0]` is the 0x6E source address,
    /// matching the Get VCP frames AppleSiliconDDC returns.
    public static func parse(_ buffer: [UInt8]) -> CapabilitiesFragment? {
        guard buffer.count >= 6, buffer[0] == 0x6E, buffer[2] == 0xE3 else { return nil }
        let declared = Int(buffer[1] & 0x7F)
        let checksumIndex = 2 + declared
        guard declared >= 3, checksumIndex < buffer.count else { return nil }
        let expected = DDCChecksum.xor(seed: 0x50, data: Array(buffer[0..<checksumIndex]))
        guard buffer[checksumIndex] == expected else { return nil }
        let bytes = Array(buffer[5..<checksumIndex])
        let text = String(bytes: bytes.filter { $0 != 0 }, encoding: .ascii) ?? ""
        let offset = (Int(buffer[3]) << 8) | Int(buffer[4])
        return CapabilitiesFragment(offset: offset, text: text)
    }

    public static func assemble(_ fragments: [CapabilitiesFragment]) -> String {
        var bytes: [UInt8] = []
        for fragment in fragments.sorted(by: { $0.offset < $1.offset }) {
            let start = max(0, fragment.offset)
            let data = Array(fragment.text.utf8)
            if start > bytes.count {
                bytes.append(contentsOf: repeatElement(UInt8(ascii: " "), count: start - bytes.count))
            }
            for (index, byte) in data.enumerated() {
                let position = start + index
                if position < bytes.count {
                    bytes[position] = byte
                } else {
                    bytes.append(byte)
                }
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}
