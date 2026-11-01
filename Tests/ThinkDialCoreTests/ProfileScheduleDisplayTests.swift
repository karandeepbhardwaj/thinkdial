import XCTest
@testable import ThinkDialCore

final class ProfileScheduleDisplayTests: XCTestCase {
    func testProfileKeepsLastValueAndItsPosition() {
        let ordered = ProfilePlan.ordered([
            VCPAssignment(code: 0x10, value: 10),
            VCPAssignment(code: 0x12, value: 5),
            VCPAssignment(code: 0x10, value: 20)
        ])
        XCTAssertEqual(ordered, [
            VCPAssignment(code: 0x12, value: 5),
            VCPAssignment(code: 0x10, value: 20)
        ])
    }

    func testBuiltinProfilesPutPresetBeforeBrightness() {
        let coding = Profile.builtins().first { $0.name == "Coding" }!
        let ordered = ProfilePlan.ordered(coding.assignments)
        XCTAssertEqual(ordered.first?.code, MCCSCatalog.Code.colorPreset)
        XCTAssertEqual(ordered.last?.code, MCCSCatalog.Code.brightness)
        XCTAssertTrue(coding.detail.contains("not a measurement"))
    }

    func testClockScheduleInterpolatesAndWrapsMidnight() {
        let points = [
            SchedulePoint(minutesFromMidnight: 22 * 60, brightness: 10),
            SchedulePoint(minutesFromMidnight: 7 * 60, brightness: 80)
        ]
        XCTAssertEqual(ScheduleMath.clockBrightness(minutes: 22 * 60, points: points), 10)
        XCTAssertEqual(ScheduleMath.clockBrightness(minutes: 7 * 60, points: points), 80)
        // 00:00 is 120 minutes into a 9-hour span from 22:00 to 07:00.
        XCTAssertEqual(ScheduleMath.clockBrightness(minutes: 0, points: points), 26)
        XCTAssertEqual(ScheduleMath.clockBrightness(minutes: 12 * 60, points: [points[0]]), 10)
        XCTAssertNil(ScheduleMath.clockBrightness(minutes: 100, points: []))
    }

    func testClockScheduleSortsAndDropsInvalidPoints() {
        let points = [
            SchedulePoint(minutesFromMidnight: 20 * 60, brightness: 10),
            SchedulePoint(minutesFromMidnight: 8 * 60, brightness: 40),
            SchedulePoint(minutesFromMidnight: 8 * 60, brightness: 50),
            SchedulePoint(minutesFromMidnight: 2000, brightness: 1)
        ]
        XCTAssertEqual(ScheduleMath.clockBrightness(minutes: 8 * 60, points: points), 50)
        XCTAssertEqual(ScheduleMath.clockBrightness(minutes: 14 * 60, points: points), 30)
    }

    func testLondonSolsticeAndNewYorkEvening() throws {
        var utc = Calendar(identifier: .gregorian)
        let utcZone = TimeZone(secondsFromGMT: 0)!
        utc.timeZone = utcZone
        let june = utc.date(from: DateComponents(timeZone: utcZone, year: 2024, month: 6, day: 21))!
        let london = try XCTUnwrap(SolarMath.sunTimes(on: june, latitude: 51.5074, longitude: -0.1278, timeZone: utcZone))
        XCTAssertEqual(hours(london.sunrise, calendar: utc), 3.719, accuracy: 0.001)
        XCTAssertEqual(hours(london.sunset, calendar: utc), 20.361, accuracy: 0.001)

        let eastern = TimeZone(secondsFromGMT: -4 * 3600)!
        var local = Calendar(identifier: .gregorian)
        local.timeZone = eastern
        let nycDay = local.date(from: DateComponents(timeZone: eastern, year: 2024, month: 6, day: 21, hour: 12))!
        let nyc = try XCTUnwrap(SolarMath.sunTimes(on: nycDay, latitude: 40.7128, longitude: -74.0060, timeZone: eastern))
        let riseHour = Double(local.component(.hour, from: nyc.sunrise)) + Double(local.component(.minute, from: nyc.sunrise)) / 60
        let setHour = Double(local.component(.hour, from: nyc.sunset)) + Double(local.component(.minute, from: nyc.sunset)) / 60
        XCTAssertEqual(Double(riseHour), 5.4, accuracy: 0.1)
        XCTAssertEqual(setHour, 20.5, accuracy: 0.1)
        XCTAssertGreaterThan(nyc.sunset, nyc.sunrise)
    }

    func testDecemberSunriseIsLaterThanJune() throws {
        var utc = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 0)!
        utc.timeZone = zone
        let june = utc.date(from: DateComponents(timeZone: zone, year: 2024, month: 6, day: 21))!
        let december = utc.date(from: DateComponents(timeZone: zone, year: 2024, month: 12, day: 21))!
        let summer = try XCTUnwrap(SolarMath.sunTimes(on: june, latitude: 51.5074, longitude: -0.1278, timeZone: zone))
        let winter = try XCTUnwrap(SolarMath.sunTimes(on: december, latitude: 51.5074, longitude: -0.1278, timeZone: zone))
        XCTAssertGreaterThan(hours(winter.sunrise, calendar: utc), hours(summer.sunrise, calendar: utc))
    }

    func testSolarBrightnessRampsAroundSunrise() throws {
        var utc = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 0)!
        utc.timeZone = zone
        let day = utc.date(from: DateComponents(timeZone: zone, year: 2024, month: 6, day: 21))!
        let times = try XCTUnwrap(SolarMath.sunTimes(on: day, latitude: 51.5074, longitude: -0.1278, timeZone: zone))
        XCTAssertEqual(
            ScheduleMath.solarBrightness(at: times.sunrise.addingTimeInterval(-3 * 3600), sunrise: times.sunrise, sunset: times.sunset, day: 70, night: 10, transitionMinutes: 0),
            10
        )
        XCTAssertEqual(
            ScheduleMath.solarBrightness(at: times.sunrise.addingTimeInterval(3600), sunrise: times.sunrise, sunset: times.sunset, day: 70, night: 10, transitionMinutes: 0),
            70
        )
        let midpoint = ScheduleMath.solarBrightness(at: times.sunrise, sunrise: times.sunrise, sunset: times.sunset, day: 80, night: 20, transitionMinutes: 40)
        XCTAssertEqual(midpoint, 50)

        var solar = SolarSchedule.unset
        solar.latitude = 51.5074
        solar.longitude = -0.1278
        solar.transitionMinutes = 0
        let noon = utc.date(from: DateComponents(timeZone: zone, year: 2024, month: 6, day: 21, hour: 12))!
        XCTAssertEqual(BrightnessSchedule.brightness(at: noon, mode: .solar, points: [], solar: solar, timeZone: zone), solar.dayBrightness)
        XCTAssertNil(BrightnessSchedule.brightness(at: noon, mode: .off, points: [], solar: solar, timeZone: zone))
        solar.latitude = nil
        XCTAssertNil(BrightnessSchedule.brightness(at: noon, mode: .solar, points: [], solar: solar, timeZone: zone))
        XCTAssertNil(SolarMath.sunTimes(on: day, latitude: 120, longitude: 0, timeZone: zone))
    }

    func testScheduleHoldoff() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(BrightnessSchedule.shouldApply(now: now, lastManualChange: nil, holdoff: 120))
        XCTAssertFalse(BrightnessSchedule.shouldApply(now: now, lastManualChange: now.addingTimeInterval(-30), holdoff: 120))
        XCTAssertTrue(BrightnessSchedule.shouldApply(now: now, lastManualChange: now.addingTimeInterval(-120), holdoff: 120))
    }

    func testLenovoAutoSelectLeavesDellAlone() {
        let displays = sampleDisplays()
        let preferred = DisplaySelector.preferred(displays)
        XCTAssertEqual(preferred?.id.raw, "lenovo")
        XCTAssertEqual(DisplaySelector.resolve(displays: displays, pinnedID: "dell")?.id.raw, "dell")
        XCTAssertEqual(DisplaySelector.resolve(displays: displays, pinnedID: nil)?.productName, "ThinkVision P34WD-40")

        let genericLenovo = DisplayDescriptor(
            id: DisplayID("other"),
            name: "ThinkVision T34w",
            vendor: "LEN",
            productName: "ThinkVision T34w",
            serialNumber: "1",
            transport: "",
            isBuiltIn: false,
            ddcAvailable: true
        )
        let both = displays + [genericLenovo]
        XCTAssertEqual(DisplaySelector.preferred(both)?.id.raw, "lenovo")
        XCTAssertEqual(DisplaySelector.preferred([genericLenovo])?.id.raw, "other")
        XCTAssertNil(DisplaySelector.preferred(displays.filter { $0.vendor == "DEL" || $0.isBuiltIn }))
    }

    func testEDIDVendorCodes() {
        XCTAssertEqual(EDIDVendor.pnpID(0x30AE), "LEN")
        XCTAssertEqual(EDIDVendor.pnpID(0x0610), "APP")
    }

    func testInputDefaultsAreNotClaimedAsFacts() {
        let bindings = InputBinding.factoryDefaults()
        XCTAssertNil(bindings.first { $0.id == InputBinding.usbC }?.value)
        XCTAssertEqual(bindings.first { $0.id == InputBinding.displayPort }?.value, 0x0F)
        XCTAssertEqual(bindings.first { $0.id == InputBinding.hdmi }?.value, 0x11)
        XCTAssertTrue(bindings.allSatisfy { $0.verifiedOnThisModel == false })
        XCTAssertTrue(InputCandidateCatalog.all.allSatisfy { $0.verifiedOnP34WD40 == false && !$0.note.isEmpty })
        XCTAssertTrue(InputCandidateCatalog.all.contains { $0.value == 0x1B && $0.basis == .otherVendorReport })
        XCTAssertTrue(InputCandidateCatalog.all.contains { $0.value == 0x13 && $0.basis == .olderLenovoReport })
        XCTAssertFalse(InputSwitchPolicy.allows(confirmed: false))
        XCTAssertTrue(InputSwitchPolicy.allows(confirmed: true))
        XCTAssertGreaterThan(InputCandidateCatalog.disconnectWarning.count, 40)
    }

    func testDisplayListPrefersControllableDuplicate() {
        let blind = DisplayDescriptor(id: DisplayID("a"), name: "Panel", vendor: "LEN", productName: "P", serialNumber: "", transport: "", isBuiltIn: false, ddcAvailable: false)
        let live = DisplayDescriptor(id: DisplayID("a"), name: "Panel", vendor: "LEN", productName: "P", serialNumber: "", transport: "DP", isBuiltIn: false, ddcAvailable: true)
        let deduped = DisplayList.deduplicated([blind, live])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertTrue(deduped[0].ddcAvailable)
        XCTAssertEqual(deduped[0].transport, "DP")
    }

    private func sampleDisplays() -> [DisplayDescriptor] {
        [
            DisplayDescriptor(id: DisplayID("builtin"), name: "Color LCD", vendor: "APP", productName: "Color LCD", serialNumber: "", transport: "Internal", isBuiltIn: true, ddcAvailable: false),
            DisplayDescriptor(id: DisplayID("lenovo"), name: "ThinkVision P34WD-40", vendor: "LEN", productName: "ThinkVision P34WD-40", serialNumber: "SN", transport: "USB-C", isBuiltIn: false, ddcAvailable: true),
            DisplayDescriptor(id: DisplayID("dell"), name: "DELL U2723QE", vendor: "DEL", productName: "DELL U2723QE", serialNumber: "SN2", transport: "DP", isBuiltIn: false, ddcAvailable: true)
        ]
    }

    private func hours(_ date: Date, calendar: Calendar) -> Double {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        return Double(hour) + Double(minute) / 60 + Double(second) / 3600
    }
}
