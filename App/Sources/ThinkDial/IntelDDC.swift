import CoreGraphics
import Foundation
import ThinkDialCore
import ThinkDialI2C

/// Intel DDC/CI over the public IOFramebuffer I2C interface.
/// The IOI2CRequest struct is filled in ThinkDialI2C.c. This file only matches displays.
/// Apple Silicon uses AppleSiliconDDC instead. Nothing here is verified on a P34WD-40.
final class IntelDDC: @unchecked Sendable {
    private var framebuffers: [String: UInt32] = [:]

    deinit {
        for service in framebuffers.values where service != 0 {
            TDReleaseService(service)
        }
    }

    func displays() -> [DisplayDescriptor] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.prefix(Int(count)).map { displayID in
            let vendorNumber = CGDisplayVendorNumber(displayID)
            let model = CGDisplayModelNumber(displayID)
            let serial = CGDisplaySerialNumber(displayID)
            let unit = CGDisplayUnitNumber(displayID)
            let vendor = EDIDVendor.pnpID(vendorNumber)
            let builtin = TDDisplayIsBuiltin(displayID) != 0
            let matched: UInt32 = builtin ? 0 : TDCopyFramebuffer(vendorNumber, model, serial, unit)
            let product = productName(of: matched)
            let title = product.isEmpty ? "\(vendor) \(model)" : product
            let id = DisplayID("cg:\(vendor):\(model):\(serial):\(unit)")
            if matched != 0 {
                if let previous = framebuffers[id.raw], previous != matched {
                    TDReleaseService(previous)
                }
                framebuffers[id.raw] = matched
            }
            return DisplayDescriptor(
                id: id,
                name: title,
                vendor: vendor,
                productName: product.isEmpty ? title : product,
                serialNumber: serial == 0 ? "" : String(serial),
                transport: "I2C (Intel fallback)",
                isBuiltIn: builtin,
                ddcAvailable: !builtin && matched != 0
            )
        }
    }

    func read(display: DisplayID, code: UInt8) throws -> VCPValue {
        let send = getRequest(code)
        guard let reply = transact(display: display, send: send, replyCount: 11) else {
            throw DDCError.readFailed(code)
        }
        guard let value = VCPReply.parseGet(buffer: reply, expectedCode: code) else {
            throw DDCError.readFailed(code)
        }
        return value
    }

    func write(display: DisplayID, code: UInt8, value: UInt16) throws {
        let send = setRequest(code, value: value)
        var sent = false
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.02)
            if transact(display: display, send: send, replyCount: 0) != nil {
                sent = true
            }
        }
        if !sent { throw DDCError.writeFailed(code) }
    }

    func readCapabilities(display: DisplayID) -> String? {
        var fragments: [CapabilitiesFragment] = []
        var offset = 0
        for _ in 0..<24 {
            let page = [0x51] + CapabilitiesRequest.payload(offset: offset)
            guard let reply = transact(display: display, send: page, replyCount: 48),
                  let fragment = CapabilitiesReply.parse(reply),
                  !fragment.text.isEmpty
            else { break }
            fragments.append(fragment)
            let next = fragment.offset + fragment.text.utf8.count
            if next <= offset { break }
            offset = next
        }
        let text = CapabilitiesReply.assemble(fragments).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("vcp") || text.contains("prot") else { return nil }
        return text
    }

    private func getRequest(_ code: UInt8) -> [UInt8] {
        var data: [UInt8] = [0x51, 0x82, 0x01, code, 0]
        data[4] = data.dropLast().reduce(0x6E, ^)
        return data
    }

    private func setRequest(_ code: UInt8, value: UInt16) -> [UInt8] {
        var data: [UInt8] = [0x51, 0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        data[6] = data.dropLast().reduce(0x6E, ^)
        return data
    }

    /// Nil means the bus rejected the packet. An empty array is a write that was accepted.
    private func transact(display: DisplayID, send: [UInt8], replyCount: Int) -> [UInt8]? {
        guard let framebuffer = framebuffers[display.raw], framebuffer != 0 else { return nil }
        var reply = [UInt8](repeating: 0, count: max(0, replyCount))
        let status: Int32 = send.withUnsafeBufferPointer { sendBuffer in
            guard let sendBase = sendBuffer.baseAddress else { return 1 }
            if replyCount == 0 {
                return TDFramebufferDDC(framebuffer, sendBase, UInt32(send.count), nil, 0)
            }
            return reply.withUnsafeMutableBufferPointer { replyBuffer in
                TDFramebufferDDC(framebuffer, sendBase, UInt32(send.count), replyBuffer.baseAddress, UInt32(replyCount))
            }
        }
        guard status == 0 else { return nil }
        return replyCount == 0 ? [] : reply
    }

    private func productName(of framebuffer: UInt32) -> String {
        guard framebuffer != 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: 128)
        guard TDCopyProductName(framebuffer, &bytes, Int32(bytes.count)) != 0 else { return "" }
        return String(cString: bytes)
    }
}
