import AppleSiliconDDC
import Foundation
import ThinkDialCore
import os

/// Talks to real displays. Apple Silicon goes through AppleSiliconDDC. Intel uses IOFramebuffer I2C.
/// Every IOKit call stays on `queue`, so the menu bar never waits on DDC sleeps.
final class HardwareDDCBackend: DDCBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.thinkdial.ddc")
    private let intel = IntelDDC()
    private var armServices: [String: AppleSiliconDDC.IOregService] = [:]
    private let log = Logger(subsystem: "app.thinkdial.ThinkDial", category: "ddc")

    func listDisplays() async throws -> [DisplayDescriptor] {
        try await onQueue {
            if AppleSiliconDDC.isArm64 {
                return self.refreshArmDisplays()
            }
            return self.intel.displays()
        }
    }

    func read(display: DisplayID, code: UInt8) async throws -> VCPValue {
        try await onQueue {
            if AppleSiliconDDC.isArm64 {
                return try self.armRead(display: display, code: code)
            }
            return try self.intel.read(display: display, code: code)
        }
    }

    func write(display: DisplayID, code: UInt8, value: UInt16) async throws {
        try await onQueue {
            if AppleSiliconDDC.isArm64 {
                try self.armWrite(display: display, code: code, value: value)
            } else {
                try self.intel.write(display: display, code: code, value: value)
            }
        }
    }

    func readCapabilities(display: DisplayID) async throws -> String? {
        try await onQueue {
            if AppleSiliconDDC.isArm64 {
                guard let service = self.armServices[display.raw]?.service else { return nil }
                return CapabilitiesTransport.readString(service: thinkDialServicePointer(service))
            }
            return self.intel.readCapabilities(display: display)
        }
    }

    private func refreshArmDisplays() -> [DisplayDescriptor] {
        let services = AppleSiliconDDC.getIoregServicesForMatching()
        var cached: [String: AppleSiliconDDC.IOregService] = [:]
        var displays: [DisplayDescriptor] = []
        for service in services {
            let descriptor = Self.descriptor(from: service)
            guard let descriptor else { continue }
            if let existing = cached[descriptor.id.raw] {
                if existing.service == nil, service.service != nil {
                    cached[descriptor.id.raw] = service
                }
            } else {
                cached[descriptor.id.raw] = service
            }
            displays.append(descriptor)
        }
        armServices = cached
        let deduped = DisplayList.deduplicated(displays)
        log.debug("Matched \(deduped.count, privacy: .public) displays via AppleSiliconDDC")
        return deduped
    }

    private func armRead(display: DisplayID, code: UInt8) throws -> VCPValue {
        guard let service = armServices[display.raw]?.service else { throw DDCError.notConnected }
        guard let value = AppleSiliconDDC.read(
            service: service,
            command: code,
            writeSleepTime: 10_000,
            numOfWriteCycles: 1,
            readSleepTime: 40_000,
            numOfRetryAttemps: 0,
            retrySleepTime: 10_000
        ) else {
            throw DDCError.readFailed(code)
        }
        return VCPValue(current: value.current, maximum: value.max)
    }

    private func armWrite(display: DisplayID, code: UInt8, value: UInt16) throws {
        guard let service = armServices[display.raw]?.service else { throw DDCError.notConnected }
        let ok = AppleSiliconDDC.write(
            service: service,
            command: code,
            value: value,
            writeSleepTime: 10_000,
            numOfWriteCycles: 1,
            numOfRetryAttemps: 0,
            retrySleepTime: 10_000
        )
        if !ok { throw DDCError.writeFailed(code) }
    }

    private static func descriptor(from service: AppleSiliconDDC.IOregService) -> DisplayDescriptor? {
        let vendor = service.manufacturerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = service.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let empty = service.edidUUID.isEmpty && vendor.isEmpty && product.isEmpty && service.transportUpstream.isEmpty
        if empty { return nil }
        let builtin = service.location.caseInsensitiveCompare("Internal") == .orderedSame
            || vendor.uppercased() == "APP"
            || product.localizedCaseInsensitiveContains("Color LCD")
        let name = product.isEmpty ? (vendor.isEmpty ? "External display" : vendor) : product
        let idSource = !service.edidUUID.isEmpty ? service.edidUUID : (!service.ioDisplayLocation.isEmpty ? service.ioDisplayLocation : "\(vendor)|\(product)|\(service.alphanumericSerialNumber)")
        let transportParts = [service.transportUpstream, service.transportDownstream].filter { !$0.isEmpty }
        let transport = transportParts.isEmpty ? service.location : transportParts.joined(separator: " → ")
        return DisplayDescriptor(
            id: DisplayID(idSource),
            name: name,
            vendor: vendor,
            productName: product.isEmpty ? name : product,
            serialNumber: service.alphanumericSerialNumber,
            transport: transport,
            isBuiltIn: builtin,
            ddcAvailable: service.service != nil && !builtin
        )
    }

    private func onQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
