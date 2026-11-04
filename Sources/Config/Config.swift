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

/// A color at exactly the precision `config.json` stores: 8 bits per channel.
/// Because memory and disk hold the same values, a saved color always reloads
/// equal, which `AppDelegate`'s config-changed check relies on. A `String`
/// `RawRepresentable` gets its `Codable` from the standard library: it encodes
/// as `#RRGGBB`, and a malformed string throws `DecodingError`.
struct HexColor: RawRepresentable, Codable, Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(color: Color) {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Self.channel(ns.redComponent),
            green: Self.channel(ns.greenComponent),
            blue: Self.channel(ns.blueComponent)
        )
    }

    init?(rawValue: String) {
        var s = rawValue.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: UInt8(truncatingIfNeeded: v >> 16),
            green: UInt8(truncatingIfNeeded: v >> 8),
            blue: UInt8(truncatingIfNeeded: v)
        )
    }

    var rawValue: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var color: Color {
        Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }

    private static func channel(_ component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((component * 255).rounded()))
    }
}
