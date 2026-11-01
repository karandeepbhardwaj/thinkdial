import XCTest
@testable import ThinkDialCore

final class CapabilitiesAndProbeTests: XCTestCase {
    func testSimulatedStringIsObviouslyFake() {
        let parsed = CapabilitiesParser.parse(MockDDCBackend.simulatedCapabilities)
        XCTAssertEqual(parsed.model, "ThinkDialSim")
        XCTAssertEqual(parsed.mccsVersion, "2.2")
        XCTAssertEqual(parsed.prot, "monitor")
        XCTAssertTrue(parsed.raw.contains("SIMULATED"))
        XCTAssertEqual(parsed.feature(0x14)?.values, [0x01, 0x05, 0x08, 0x0B])
        XCTAssertEqual(parsed.feature(0x60)?.values, [0x0F, 0x11, 0x1B])
        XCTAssertEqual(parsed.feature(0xE0)?.values, [])
        XCTAssertTrue(parsed.commands.contains(0xF3))
    }

    func testPublicSampleCapabilitiesString() {
        // A published capabilities string from a different monitor (Acer R240HY), used only to lock the parser.
        let raw = "(prot(monitor)type(LCD)model(R240HY)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B) 16 18 1A 60(01 03 0F 11) 62 8D(01 02) D6(01 04 05) DF)mccs_ver(2.1))"
        let parsed = CapabilitiesParser.parse(raw)
        XCTAssertEqual(parsed.model, "R240HY")
        XCTAssertEqual(parsed.mccsVersion, "2.1")
        XCTAssertEqual(parsed.feature(0x60)?.values, [0x01, 0x03, 0x0F, 0x11])
        XCTAssertEqual(parsed.feature(0x8D)?.values, [0x01, 0x02])
        XCTAssertEqual(parsed.feature(0xD6)?.values, [0x01, 0x04, 0x05])
        XCTAssertEqual(parsed.feature(0x10)?.values, [])
    }

    func testParserToleratesSpacingInsideValueLists() {
        let parsed = CapabilitiesParser.parse("(vcp(60( 11 12 0F 10) 10))")
        XCTAssertEqual(parsed.feature(0x60)?.values, [0x11, 0x12, 0x0F, 0x10])
        XCTAssertNotNil(parsed.feature(0x10))
    }

    func testProbeMergeKeepsRespondersAndCapabilityCodes() {
        let capabilities = CapabilitiesParser.parse("(vcp(10 12 E1))")
        let readings = [
            ProbeInterpreter.reading(code: 0x10, result: .success(VCPValue(current: 40, maximum: 100))),
            ProbeInterpreter.reading(code: 0x12, result: .failure(DDCError.unsupported(0x12))),
            ProbeInterpreter.reading(code: 0xE0, result: .success(VCPValue(current: 7, maximum: 10)))
        ]
        let rows = ProbeMerge.rows(capabilities: capabilities, readings: readings, labels: [0xE0: "Vendor thing"])
        XCTAssertEqual(rows.map(\.code), [0x10, 0x12, 0xE0, 0xE1])
        XCTAssertEqual(rows.first { $0.code == 0x10 }?.mccsName, "Brightness")
        XCTAssertEqual(rows.first { $0.code == 0x12 }?.responded, false)
        XCTAssertEqual(rows.first { $0.code == 0x12 }?.inCapabilities, true)
        XCTAssertEqual(rows.first { $0.code == 0xE0 }?.label, "Vendor thing")
        XCTAssertNil(rows.first { $0.code == 0xE0 }?.mccsName)
        XCTAssertEqual(rows.first { $0.code == 0xE1 }?.responded, false)
    }

    func testProbeExportRoundTripAndSchemaGuard() throws {
        let report = ProbeReport(
            displayName: "ThinkVision P34WD-40",
            displayID: "abc",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            capabilitiesRaw: MockDDCBackend.simulatedCapabilities,
            readings: [ProbeReading(code: 0x10, responded: true, current: 40, maximum: 100, message: nil)],
            labels: [CodeLabel(code: 0xE0, label: "KVM?")],
            pinnedControls: [CustomControl(code: 0xE0, label: "KVM?", kind: .slider, maximum: 100)]
        )
        let data = try ProbeExport.encode(report)
        let decoded = try ProbeExport.decode(data)
        XCTAssertEqual(decoded.displayName, report.displayName)
        XCTAssertEqual(decoded.readings, report.readings)
        XCTAssertEqual(decoded.pinnedControls.first?.code, 0xE0)
        XCTAssertTrue(decoded.disclaimer.contains("not a Lenovo specification"))

        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["schemaVersion"] = 99
        let foreign = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try ProbeExport.decode(foreign))
    }

    func testPinMergeReplacesSameCode() {
        let existing = [CustomControl(id: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!, code: 0xE0, label: "Old", kind: .slider)]
        let imported = [CustomControl(code: 0xE0, label: "New", kind: .toggle), CustomControl(code: 0xE2, label: "Other", kind: .picker)]
        let merged = ProbeLibrary.mergePins(existing: existing, imported: imported)
        XCTAssertEqual(merged.map(\.code), [0xE0, 0xE2])
        XCTAssertEqual(merged[0].label, "New")
        XCTAssertEqual(merged[0].id, existing[0].id)
        XCTAssertEqual(merged[0].kind, .toggle)
    }

    func testWriteGateNeedsBothFlags() {
        XCTAssertFalse(ProbeWritePolicy.allows(armed: false, confirmedThisWrite: true))
        XCTAssertFalse(ProbeWritePolicy.allows(armed: true, confirmedThisWrite: false))
        XCTAssertTrue(ProbeWritePolicy.allows(armed: true, confirmedThisWrite: true))
        XCTAssertFalse(ProbeWritePolicy.armingWarning.isEmpty)
    }
}
