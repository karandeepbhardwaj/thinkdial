import CoreGraphics
import Foundation
import IOKit
import IOKit.i2c
import ThinkDialCore

/// Best-effort DDC/CI over IOFramebuffer I2C for Intel Macs.
/// Apple Silicon uses AppleSiliconDDC instead. This file still typechecks on arm64 so the
/// fallback is not an unbuilt `#if`. It follows the public IOKit transaction shape, not a
/// copied MonitorControl source file. Nothing here is verified on a P34WD-40.
final class IntelDDC: @unchecked Sendable {
    private var framebuffers: [String: io_service_t] = [:]

    deinit {
        for service in framebuffers.values where service != 0 {
            IOObjectRelease(service)
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
            let vendor = EDIDVendor.pnpID(vendorNumber)
            let builtin = CGDisplayIsBuiltin(displayID)
            let matched = framebuffer(for: displayID, vendor: vendorNumber, model: model, serial: serial)
            let product = matched.flatMap { productName(of: $0) } ?? ""
            let title = product.isEmpty ? "\(vendor) \(model)" : product
            let id = DisplayID("cg:\(vendor):\(model):\(serial):\(CGDisplayUnitNumber(displayID))")
            if let matched {
                if let previous = framebuffers[id.raw], previous != matched {
                    IOObjectRelease(previous)
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
                ddcAvailable: !builtin && matched != nil
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

    /// Nil means the transaction failed. An empty array means a write with no reply was accepted.
    private func transact(display: DisplayID, send: [UInt8], replyCount: Int) -> [UInt8]? {
        guard let framebuffer = framebuffers[display.raw] else { return nil }
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS, busCount > 0 else { return nil }
        for bus in 0..<busCount {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(framebuffer, IOOptionBits(bus), &interface) == KERN_SUCCESS, interface != 0 else {
                continue
            }
            defer { IOObjectRelease(interface) }
            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, 0, &connect) == KERN_SUCCESS, let connect else { continue }
            defer { IOI2CInterfaceClose(connect, 0) }

            var sendBytes = send
            var replyBytes = [UInt8](repeating: 0, count: replyCount)
            let accepted: Bool = sendBytes.withUnsafeMutableBytes { sendRaw in
                replyBytes.withUnsafeMutableBytes { replyRaw in
                    var request = IOI2CRequest()
                    request.commFlags = 0
                    request.sendAddress = 0x6E
                    request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                    request.sendBuffer = vm_address_t(bitPattern: sendRaw.baseAddress)
                    request.sendBytes = UInt32(send.count)
                    request.minReplyDelay = 10
                    if replyCount == 0 {
                        request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
                        request.replyBytes = 0
                    } else {
                        request.replyAddress = 0x6F
                        request.replySubAddress = 0x51
                        request.replyTransactionType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
                        request.replyBuffer = vm_address_t(bitPattern: replyRaw.baseAddress)
                        request.replyBytes = UInt32(replyCount)
                    }
                    let result = IOI2CSendRequest(connect, 0, &request)
                    return result == KERN_SUCCESS && request.result == KERN_SUCCESS
                }
            }
            if accepted {
                return replyCount == 0 ? [] : replyBytes
            }
        }
        return nil
    }

    private func framebuffer(for displayID: CGDirectDisplayID, vendor: UInt32, model: UInt32, serial: UInt32) -> io_service_t? {
        if CGDisplayIsBuiltin(displayID) { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
            let portVendor = number(kDisplayVendorID as String, in: info)
            let portModel = number(kDisplayProductID as String, in: info)
            let portSerial = number(kDisplaySerialNumber as String, in: info)
            guard portVendor == vendor, portModel == model, portSerial == serial else {
                IOObjectRelease(service)
                continue
            }
            if let location = info[kIODisplayLocationKey as String] as? String,
               let unit = unitNumber(in: location),
               unit != CGDisplayUnitNumber(displayID) {
                IOObjectRelease(service)
                continue
            }
            var buses: IOItemCount = 0
            guard IOFBGetI2CInterfaceCount(service, &buses) == KERN_SUCCESS, buses > 0 else {
                IOObjectRelease(service)
                continue
            }
            return service
        }
        return nil
    }

    private func productName(of service: io_service_t) -> String? {
        let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
        guard let names = info["DisplayProductName"] as? NSDictionary else { return nil }
        if let english = names["en_US"] as? String, !english.isEmpty { return english }
        return names.allValues.compactMap { $0 as? String }.first
    }

    private func number(_ key: String, in dictionary: NSDictionary) -> UInt32 {
        if let value = dictionary[key] as? NSNumber { return value.uint32Value }
        return 0
    }

    private func unitNumber(in location: String) -> UInt32? {
        guard let at = location.lastIndex(of: "@") else { return nil }
        let digits = location[location.index(after: at)...].prefix { $0.isNumber }
        return UInt32(digits)
    }
}
