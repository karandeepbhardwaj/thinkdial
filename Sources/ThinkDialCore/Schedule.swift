import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public struct SchedulePoint: Codable, Equatable, Sendable {
    /// Minutes from local midnight, 0...1439.
    public var minutesFromMidnight: Int
    public var brightness: UInt16

    public init(minutesFromMidnight: Int, brightness: UInt16) {
        self.minutesFromMidnight = minutesFromMidnight
        self.brightness = brightness
    }
}

public struct SolarSchedule: Codable, Equatable, Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var dayBrightness: UInt16
    public var nightBrightness: UInt16
    /// Minutes, centered on sunrise and sunset, spent fading between night and day.
    public var transitionMinutes: Int

    public init(latitude: Double?, longitude: Double?, dayBrightness: UInt16, nightBrightness: UInt16, transitionMinutes: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.dayBrightness = dayBrightness
        self.nightBrightness = nightBrightness
        self.transitionMinutes = transitionMinutes
    }

    public static let unset = SolarSchedule(
        latitude: nil,
        longitude: nil,
        dayBrightness: 70,
        nightBrightness: 12,
        transitionMinutes: 40
    )
}

public enum ScheduleMode: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case clock
    case solar
}

public enum ScheduleMath {
    public static func clockBrightness(minutes: Int, points: [SchedulePoint]) -> UInt16? {
        var lastByMinute: [Int: UInt16] = [:]
        for point in points where (0..<1440).contains(point.minutesFromMidnight) {
            lastByMinute[point.minutesFromMidnight] = point.brightness
        }
        let cleaned = lastByMinute.keys.sorted().map {
            SchedulePoint(minutesFromMidnight: $0, brightness: lastByMinute[$0]!)
        }
        guard let first = cleaned.first else { return nil }
        if cleaned.count == 1 { return first.brightness }
        let minute = ((minutes % 1440) + 1440) % 1440
        if let nextIndex = cleaned.firstIndex(where: { $0.minutesFromMidnight > minute }) {
            if nextIndex == 0 {
                return fade(from: cleaned[cleaned.count - 1], to: cleaned[0], minute: minute, wrapping: true)
            }
            return fade(from: cleaned[nextIndex - 1], to: cleaned[nextIndex], minute: minute, wrapping: false)
        }
        return fade(from: cleaned[cleaned.count - 1], to: cleaned[0], minute: minute, wrapping: true)
    }

    public static func solarBrightness(
        at now: Date,
        sunrise: Date,
        sunset: Date,
        day: UInt16,
        night: UInt16,
        transitionMinutes: Int
    ) -> UInt16 {
        let transition = TimeInterval(max(0, transitionMinutes)) * 60
        if transition == 0 {
            return (now >= sunrise && now < sunset) ? day : night
        }
        let half = transition / 2
        let upStart = sunrise.addingTimeInterval(-half)
        let upEnd = sunrise.addingTimeInterval(half)
        let downStart = sunset.addingTimeInterval(-half)
        let downEnd = sunset.addingTimeInterval(half)
        if now >= upEnd && now < downStart { return day }
        if now >= upStart && now < upEnd {
            let span = upEnd.timeIntervalSince(upStart)
            let fraction = span == 0 ? 1 : now.timeIntervalSince(upStart) / span
            return lerp(night, day, fraction)
        }
        if now >= downStart && now < downEnd {
            let fraction = now.timeIntervalSince(downStart) / transition
            return lerp(day, night, fraction)
        }
        return night
    }

    private static func fade(from previous: SchedulePoint, to next: SchedulePoint, minute: Int, wrapping: Bool) -> UInt16 {
        let start = previous.minutesFromMidnight
        let end = wrapping ? next.minutesFromMidnight + 1440 : next.minutesFromMidnight
        let current = wrapping && minute < start ? minute + 1440 : minute
        let span = end - start
        if span <= 0 { return previous.brightness }
        return lerp(previous.brightness, next.brightness, Double(current - start) / Double(span))
    }

    static func lerp(_ start: UInt16, _ end: UInt16, _ fraction: Double) -> UInt16 {
        let t = min(1, max(0, fraction))
        let value = Double(start) + (Double(end) - Double(start)) * t
        return UInt16(value.rounded())
    }
}

public enum SolarMath {
    public static let officialZenith = 90.833

    /// Sunrise and sunset for the local calendar day of `day`.
    /// Uses the public-domain “Sunrise/Sunset Algorithm” (official zenith 90.833°).
    /// Returns nil for polar day or night, or for coordinates outside the valid range.
    public static func sunTimes(
        on day: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone,
        zenith: Double = SolarMath.officialZenith
    ) -> (sunrise: Date, sunset: Date)? {
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) else { return nil }
        guard
            let rise = universalHours(dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, rising: true, zenith: zenith),
            let set = universalHours(dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, rising: false, zenith: zenith)
        else { return nil }

        var utc = Calendar(identifier: .gregorian)
        let utcZone = TimeZone(secondsFromGMT: 0)!
        utc.timeZone = utcZone
        let components = DateComponents(
            timeZone: utcZone,
            year: calendar.component(.year, from: day),
            month: calendar.component(.month, from: day),
            day: calendar.component(.day, from: day)
        )
        guard let midnight = utc.date(from: components) else { return nil }
        let sunrise = midnight.addingTimeInterval(rise * 3600)
        var sunset = midnight.addingTimeInterval(set * 3600)
        if sunset <= sunrise {
            sunset = sunset.addingTimeInterval(86_400)
        }
        return (sunrise, sunset)
    }

    static func universalHours(dayOfYear: Int, latitude: Double, longitude: Double, rising: Bool, zenith: Double) -> Double? {
        let lngHour = longitude / 15
        let t = Double(dayOfYear) + (((rising ? 6.0 : 18.0) - lngHour) / 24)
        let meanAnomaly = (0.9856 * t) - 3.289
        var longitudeSun = meanAnomaly + (1.916 * sind(meanAnomaly)) + (0.020 * sind(2 * meanAnomaly)) + 282.634
        longitudeSun = mod(longitudeSun, 360)
        var rightAscension = atand(0.91764 * tand(longitudeSun))
        rightAscension = mod(rightAscension, 360)
        let longitudeQuadrant = (longitudeSun / 90).rounded(.down) * 90
        let ascensionQuadrant = (rightAscension / 90).rounded(.down) * 90
        rightAscension = (rightAscension + (longitudeQuadrant - ascensionQuadrant)) / 15
        let sinDeclination = 0.39782 * sind(longitudeSun)
        let cosDeclination = cos(asin(sinDeclination))
        let cosHour = (cosd(zenith) - (sinDeclination * sind(latitude))) / (cosDeclination * cosd(latitude))
        if cosHour > 1 || cosHour < -1 { return nil }
        let hourAngle = (rising ? (360 - acosd(cosHour)) : acosd(cosHour)) / 15
        let localMean = hourAngle + rightAscension - (0.06571 * t) - 6.622
        return mod(localMean - lngHour, 24)
    }

    private static func sind(_ degrees: Double) -> Double { sin(degrees * .pi / 180) }
    private static func cosd(_ degrees: Double) -> Double { cos(degrees * .pi / 180) }
    private static func tand(_ degrees: Double) -> Double { tan(degrees * .pi / 180) }
    private static func acosd(_ value: Double) -> Double { acos(value) * 180 / .pi }
    private static func atand(_ value: Double) -> Double { atan(value) * 180 / .pi }

    private static func mod(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }
}

public enum BrightnessSchedule {
    public static func brightness(
        at date: Date,
        mode: ScheduleMode,
        points: [SchedulePoint],
        solar: SolarSchedule,
        timeZone: TimeZone
    ) -> UInt16? {
        switch mode {
        case .off:
            return nil
        case .clock:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            return ScheduleMath.clockBrightness(minutes: minutes, points: points)
        case .solar:
            guard let latitude = solar.latitude, let longitude = solar.longitude else { return nil }
            guard let times = SolarMath.sunTimes(on: date, latitude: latitude, longitude: longitude, timeZone: timeZone) else {
                return nil
            }
            return ScheduleMath.solarBrightness(
                at: date,
                sunrise: times.sunrise,
                sunset: times.sunset,
                day: solar.dayBrightness,
                night: solar.nightBrightness,
                transitionMinutes: solar.transitionMinutes
            )
        }
    }

    /// After a manual slider move, leave the monitor alone until `holdoff` has passed.
    public static func shouldApply(now: Date, lastManualChange: Date?, holdoff: TimeInterval) -> Bool {
        guard let lastManualChange else { return true }
        return now.timeIntervalSince(lastManualChange) >= holdoff
    }
}
