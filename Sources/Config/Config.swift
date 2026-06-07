import SwiftUI

struct Config: Codable, Equatable {
    var version: Int
    var searchPaths: [String]
    var highlightColor: HexColor?
    var alwaysShowHint: Bool

    static let `default` = Config(
        version: 1,
        searchPaths: ["/Applications", "/System/Applications"],
        highlightColor: nil,
        alwaysShowHint: false
    )

    init(
        version: Int,
        searchPaths: [String],
        highlightColor: HexColor? = nil,
        alwaysShowHint: Bool = false
    ) {
        self.version = version
        self.searchPaths = searchPaths
        self.highlightColor = highlightColor
        self.alwaysShowHint = alwaysShowHint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.searchPaths = try c.decode([String].self, forKey: .searchPaths)
        self.highlightColor = try c.decodeIfPresent(HexColor.self, forKey: .highlightColor)
        self.alwaysShowHint = try c.decodeIfPresent(Bool.self, forKey: .alwaysShowHint) ?? false
    }
}

struct HexColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(color: Color) {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.red = Double(ns.redComponent)
        self.green = Double(ns.greenComponent)
        self.blue = Double(ns.blueComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = HexColor.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected #RRGGBB hex string, got \(raw)"
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let r = max(0, min(255, Int((red * 255).rounded())))
        let g = max(0, min(255, Int((green * 255).rounded())))
        let b = max(0, min(255, Int((blue * 255).rounded())))
        try container.encode(String(format: "#%02X%02X%02X", r, g, b))
    }

    private static func parse(_ raw: String) -> HexColor? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return HexColor(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
