import Foundation

public struct CapabilityFeature: Equatable, Sendable {
    public var code: UInt8
    public var values: [UInt8]

    public init(code: UInt8, values: [UInt8]) {
        self.code = code
        self.values = values
    }
}

public struct ParsedCapabilities: Equatable, Sendable {
    public var raw: String
    public var prot: String?
    public var type: String?
    public var model: String?
    public var mccsVersion: String?
    public var commands: [UInt8]
    public var features: [CapabilityFeature]

    public init(
        raw: String,
        prot: String?,
        type: String?,
        model: String?,
        mccsVersion: String?,
        commands: [UInt8],
        features: [CapabilityFeature]
    ) {
        self.raw = raw
        self.prot = prot
        self.type = type
        self.model = model
        self.mccsVersion = mccsVersion
        self.commands = commands
        self.features = features
    }

    public func feature(_ code: UInt8) -> CapabilityFeature? {
        features.first { $0.code == code }
    }
}

public enum CapabilitiesParser {
    public static func parse(_ raw: String) -> ParsedCapabilities {
        let commands = hexTokens(section("cmds", in: raw) ?? "")
        return ParsedCapabilities(
            raw: raw,
            prot: section("prot", in: raw),
            type: section("type", in: raw),
            model: section("model", in: raw),
            mccsVersion: section("mccs_ver", in: raw),
            commands: commands,
            features: parseFeatures(section("vcp", in: raw) ?? "")
        )
    }

    static func section(_ name: String, in raw: String) -> String? {
        guard let range = raw.range(of: name + "(", options: .caseInsensitive) else { return nil }
        var depth = 1
        var index = range.upperBound
        let start = index
        while index < raw.endIndex {
            let character = raw[index]
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 {
                    return String(raw[start..<index])
                }
            }
            index = raw.index(after: index)
        }
        return nil
    }

    static func parseFeatures(_ body: String) -> [CapabilityFeature] {
        var features: [CapabilityFeature] = []
        var index = body.startIndex
        func skipSpace() {
            while index < body.endIndex, body[index] == " " || body[index] == "\n" || body[index] == "\t" {
                index = body.index(after: index)
            }
        }
        while index < body.endIndex {
            skipSpace()
            if index >= body.endIndex { break }
            let tokenStart = index
            while index < body.endIndex, body[index].isHexDigit {
                index = body.index(after: index)
            }
            if tokenStart == index {
                index = body.index(after: index)
                continue
            }
            let token = String(body[tokenStart..<index])
            guard let code = UInt8(token, radix: 16) else { continue }
            skipSpace()
            var values: [UInt8] = []
            if index < body.endIndex, body[index] == "(" {
                index = body.index(after: index)
                while index < body.endIndex, body[index] != ")" {
                    skipSpace()
                    if index < body.endIndex, body[index] == ")" { break }
                    let valueStart = index
                    while index < body.endIndex, body[index].isHexDigit {
                        index = body.index(after: index)
                    }
                    if valueStart == index {
                        if index < body.endIndex, body[index] != ")" {
                            index = body.index(after: index)
                        }
                        continue
                    }
                    if let value = UInt8(String(body[valueStart..<index]), radix: 16) {
                        values.append(value)
                    }
                }
                if index < body.endIndex, body[index] == ")" {
                    index = body.index(after: index)
                }
            }
            features.append(CapabilityFeature(code: code, values: values))
        }
        return features
    }

    private static func hexTokens(_ body: String) -> [UInt8] {
        body.split { $0 == " " || $0 == "\n" || $0 == "\t" }.compactMap { UInt8($0, radix: 16) }
    }
}
