import XCTest
@testable import ThinkDialCore

final class DDCLogicTests: XCTestCase {
    func testRequestChecksumVectors() {
        let getBrightness: [UInt8] = [0x82, 0x01, 0x10]
        XCTAssertEqual(DDCChecksum.requestChecksum(payloadIncludingLength: getBrightness), 0xAC)

        let setBrightness: [UInt8] = [0x84, 0x03, 0x10, 0x00, 0x64]
        XCTAssertEqual(DDCChecksum.requestChecksum(payloadIncludingLength: setBrightness), 0xCC)

        let capabilities = CapabilitiesRequest.payload(offset: 0)
        XCTAssertEqual(capabilities, [0x83, 0xF3, 0x00, 0x00, 0x4F])
    }

    func testGetVCPReplyRoundTrip() {
        let frame: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
        let value = VCPReply.parseGet(buffer: frame, expectedCode: 0x10)
        XCTAssertEqual(value, VCPValue(current: 50, maximum: 100))
        XCTAssertNil(VCPReply.parseGet(buffer: frame, expectedCode: 0x12))

        var corrupted = frame
        corrupted[9] = 0x33
        XCTAssertNil(VCPReply.parseGet(buffer: corrupted, expectedCode: 0x10))
    }

    func testCapabilitiesFragmentAndAssembly() {
        let text = Array("vcp(10)".utf8)
        var body: [UInt8] = [0x6E, 0x80 | UInt8(3 + text.count), 0xE3, 0x00, 0x00] + text
        body.append(DDCChecksum.xor(seed: 0x50, data: body))
        let fragment = CapabilitiesReply.parse(body)
        XCTAssertEqual(fragment, CapabilitiesFragment(offset: 0, text: "vcp(10)"))

        let second = CapabilitiesFragment(offset: 7, text: " 12)")
        XCTAssertEqual(CapabilitiesReply.assemble([fragment!, second]), "vcp(10) 12)")
        XCTAssertNil(CapabilitiesReply.parse([0x00, 0x88, 0x02]))
    }

    func testMappingScalesToReportedMaximum() {
        XCTAssertEqual(VCPMapping.raw(percent: 50, reportedMaximum: 100), 50)
        XCTAssertEqual(VCPMapping.raw(percent: 50, reportedMaximum: 200), 100)
        XCTAssertEqual(VCPMapping.raw(percent: 150, reportedMaximum: 100), 100)
        XCTAssertEqual(VCPMapping.raw(percent: -10, reportedMaximum: 100), 0)
        XCTAssertEqual(VCPMapping.percent(raw: 128, reportedMaximum: 255), 50)
        XCTAssertEqual(VCPMapping.effectiveMaximum(0), 100)
        XCTAssertEqual(VCPMapping.raw(percent: 40, reportedMaximum: 0), 40)
    }

    func testMuteAndPowerStayLabeledAsMCCS() {
        XCTAssertEqual(MuteMapping.isMuted(current: 1), true)
        XCTAssertEqual(MuteMapping.isMuted(current: 2), false)
        XCTAssertNil(MuteMapping.isMuted(current: 0))
        XCTAssertEqual(MuteMapping.value(muted: true), 1)
        XCTAssertEqual(PowerMapping.off, 0x05)
        XCTAssertFalse(PowerMapping.verifiedOnP34WD40)
    }

    func testHexParser() {
        XCTAssertEqual(VCPText.parse("0x1B"), 0x1B)
        XCTAssertEqual(VCPText.parse("x0f"), 0x0F)
        XCTAssertEqual(VCPText.parse("27"), 27)
        XCTAssertEqual(VCPText.parse(" 0X10 "), 0x10)
        XCTAssertNil(VCPText.parse(""))
        XCTAssertNil(VCPText.parse("0xGG"))
        XCTAssertNil(VCPText.parse("256", max: 255))
        XCTAssertEqual(VCPText.format(0x0F), "0x0F")
    }

    func testTimingClamps() {
        XCTAssertEqual(TimingLimits.intervalMilliseconds(1), 20)
        XCTAssertEqual(TimingLimits.intervalMilliseconds(80), 80)
        XCTAssertEqual(TimingLimits.intervalMilliseconds(99_999), 5_000)
        XCTAssertEqual(TimingLimits.attempts(0), 1)
        XCTAssertEqual(TimingLimits.attempts(3), 3)
        XCTAssertEqual(TimingLimits.attempts(40), 6)
    }
}
