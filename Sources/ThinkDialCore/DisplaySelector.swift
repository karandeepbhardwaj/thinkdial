import Foundation

public struct DisplayMatch: Equatable, Sendable {
    public var display: DisplayDescriptor
    public var score: Int
    public var reasons: [String]

    public init(display: DisplayDescriptor, score: Int, reasons: [String]) {
        self.display = display
        self.score = score
        self.reasons = reasons
    }
}

public enum EDIDVendor {
    /// Decode the 16-bit EDID manufacturer id (the value `CGDisplayVendorNumber` returns) into a PnP code.
    /// Lenovo is `0x30AE` → `LEN`. Apple is `0x0610` → `APP`.
    public static func pnpID(_ vendorNumber: UInt32) -> String {
        let value = UInt16(vendorNumber & 0xFFFF)
        let letters = [
            letter((value >> 10) & 0x1F),
            letter((value >> 5) & 0x1F),
            letter(value & 0x1F)
        ]
        return String(letters)
    }

    private static func letter(_ fiveBits: UInt16) -> Character {
        let scalar = UInt32(fiveBits & 0x1F) + 64
        return Character(UnicodeScalar(scalar) ?? UnicodeScalar(63)!)
    }
}

public enum DisplaySelector {
    /// Auto-pick a ThinkVision. A pinned id, when that display is still connected, always wins —
    /// including when the user deliberately picked a non-Lenovo panel.
    public static func resolve(displays: [DisplayDescriptor], pinnedID: String?) -> DisplayDescriptor? {
        if let pinnedID, let pinned = displays.first(where: { $0.id.raw == pinnedID }) {
            return pinned
        }
        return preferred(displays)
    }

    public static func preferred(_ displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        rank(displays).first { $0.score >= 80 }?.display
    }

    public static func rank(_ displays: [DisplayDescriptor]) -> [DisplayMatch] {
        displays.map { match(for: $0) }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.display.id < rhs.display.id
        }
    }

    public static func match(for display: DisplayDescriptor) -> DisplayMatch {
        var score = 0
        var reasons: [String] = []
        let vendor = display.vendor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let product = display.productName.lowercased()
        let name = display.name.lowercased()
        let haystack = product + " " + name

        if vendor == "len" || vendor == "lenovo" {
            score += 80
            reasons.append("EDID vendor is Lenovo")
        }
        if haystack.contains("p34wd") {
            score += 120
            reasons.append("Product name contains P34WD")
        }
        if haystack.contains("thinkvision") {
            score += 40
            reasons.append("Product name contains ThinkVision")
        }
        if display.isBuiltIn || vendor == "app" || vendor == "apple" || haystack.contains("color lcd") {
            score -= 500
            reasons.append("Built-in display")
        }
        if !display.ddcAvailable {
            score -= 200
            reasons.append("No DDC service")
        }
        if reasons.isEmpty {
            reasons.append("No Lenovo match")
        }
        return DisplayMatch(display: display, score: score, reasons: reasons)
    }
}
