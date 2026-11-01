import Foundation

/// In-memory monitor used by demo mode and tests.
/// The capabilities string is invented for the simulator. It is not a dump from a P34WD-40.
public actor MockDDCBackend: DDCBackend {
    public static let simulatedCapabilities = "(prot(monitor)type(lcd)model(ThinkDialSim)note(SIMULATED)cmds(01 02 03 F3)vcp(10 12 14(01 05 08 0B) 16 18 1A 60(0F 11 1B) 62 8D(01 02) D6(01 04 05) E0)mccs_ver(2.2))"

    public static let lenovoID = DisplayID("simulated-p34wd-40")
    public static let dellID = DisplayID("simulated-dell-u2723qe")
    public static let builtInID = DisplayID("simulated-builtin")

    public struct WriteRecord: Equatable, Sendable {
        public var display: DisplayID
        public var code: UInt8
        public var value: UInt16

        public init(display: DisplayID, code: UInt8, value: UInt16) {
            self.display = display
            self.code = code
            self.value = value
        }
    }

    private var values: [DisplayID: [UInt8: VCPValue]]
    private var readable: [DisplayID: Set<UInt8>]
    private var remainingWriteFailures = 0
    private var remainingReadFailures = 0
    private let delayNanoseconds: UInt64
    public private(set) var writeLog: [WriteRecord] = []

    public init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
        let lenovo = Self.lenovoTable()
        let dell: [UInt8: VCPValue] = [
            MCCSCatalog.Code.brightness: VCPValue(current: 30, maximum: 100),
            MCCSCatalog.Code.contrast: VCPValue(current: 50, maximum: 100)
        ]
        values = [
            Self.lenovoID: lenovo,
            Self.dellID: dell
        ]
        readable = [
            Self.lenovoID: Set(lenovo.keys),
            Self.dellID: Set(dell.keys)
        ]
    }

    public static func demo(delayNanoseconds: UInt64 = 0) -> MockDDCBackend {
        MockDDCBackend(delayNanoseconds: delayNanoseconds)
    }

    public func failNextWrites(_ count: Int) {
        remainingWriteFailures = max(0, count)
    }

    public func failNextReads(_ count: Int) {
        remainingReadFailures = max(0, count)
    }

    public func listDisplays() async throws -> [DisplayDescriptor] {
        await pause()
        return [
            DisplayDescriptor(
                id: Self.builtInID,
                name: "Color LCD",
                vendor: "APP",
                productName: "Color LCD",
                serialNumber: "",
                transport: "Internal",
                isBuiltIn: true,
                ddcAvailable: false
            ),
            DisplayDescriptor(
                id: Self.lenovoID,
                name: "ThinkVision P34WD-40",
                vendor: "LEN",
                productName: "ThinkVision P34WD-40",
                serialNumber: "SIMULATED",
                transport: "Simulated USB-C",
                isBuiltIn: false,
                ddcAvailable: true
            ),
            DisplayDescriptor(
                id: Self.dellID,
                name: "DELL U2723QE",
                vendor: "DEL",
                productName: "DELL U2723QE",
                serialNumber: "SIMULATED",
                transport: "Simulated DisplayPort",
                isBuiltIn: false,
                ddcAvailable: true
            )
        ]
    }

    public func read(display: DisplayID, code: UInt8) async throws -> VCPValue {
        await pause()
        if remainingReadFailures > 0 {
            remainingReadFailures -= 1
            throw DDCError.readFailed(code)
        }
        guard values[display] != nil else { throw DDCError.notConnected }
        guard readable[display, default: []].contains(code), let value = values[display]?[code] else {
            throw DDCError.unsupported(code)
        }
        return value
    }

    public func write(display: DisplayID, code: UInt8, value: UInt16) async throws {
        await pause()
        guard var table = values[display] else { throw DDCError.notConnected }
        if remainingWriteFailures > 0 {
            remainingWriteFailures -= 1
            throw DDCError.writeFailed(code)
        }
        let maximum = table[code]?.maximum ?? 100
        table[code] = VCPValue(current: value, maximum: maximum)
        values[display] = table
        readable[display, default: []].insert(code)
        writeLog.append(WriteRecord(display: display, code: code, value: value))
    }

    public func readCapabilities(display: DisplayID) async throws -> String? {
        await pause()
        guard display == Self.lenovoID else { return nil }
        return Self.simulatedCapabilities
    }

    public func writes(code: UInt8, display: DisplayID) -> [UInt16] {
        writeLog.filter { $0.code == code && $0.display == display }.map(\.value)
    }

    private func pause() async {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    private static func lenovoTable() -> [UInt8: VCPValue] {
        [
            0x02: VCPValue(current: 1, maximum: 255),
            MCCSCatalog.Code.brightness: VCPValue(current: 40, maximum: 100),
            MCCSCatalog.Code.contrast: VCPValue(current: 70, maximum: 100),
            MCCSCatalog.Code.colorPreset: VCPValue(current: 0x05, maximum: 0x0B),
            MCCSCatalog.Code.gainRed: VCPValue(current: 50, maximum: 100),
            MCCSCatalog.Code.gainGreen: VCPValue(current: 50, maximum: 100),
            MCCSCatalog.Code.gainBlue: VCPValue(current: 50, maximum: 100),
            MCCSCatalog.Code.inputSource: VCPValue(current: 0x0F, maximum: 0x1B),
            MCCSCatalog.Code.volume: VCPValue(current: 20, maximum: 100),
            MCCSCatalog.Code.mute: VCPValue(current: MuteMapping.unmute, maximum: MuteMapping.unmute),
            0xAC: VCPValue(current: 5330, maximum: 0),
            0xAE: VCPValue(current: 6000, maximum: 0),
            MCCSCatalog.Code.powerMode: VCPValue(current: PowerMapping.on, maximum: PowerMapping.off),
            0xDF: VCPValue(current: 0x0202, maximum: 0xFFFF),
            0xE0: VCPValue(current: 40, maximum: 100)
        ]
    }
}
