import SwiftUI
import AppKit

/// The Broadsheet design system's tokens, as the app's colours and type.
///
/// Broadsheet is a paper-light system. NFR-9 asks the interface to follow the
/// system appearance, so each token is a dynamic colour: the light value is the
/// system's own, and the dark value is its counterpart from the same ramp.
/// Nothing here hard-codes a colour anywhere else in the app.
enum Broadsheet {

    // MARK: Ramps

    private static let neutralRamp = [
        0xf8f4f4, 0xeae7e7, 0xd7d3d3, 0xbab6b6, 0x9b9797,
        0x7d7979, 0x605d5d, 0x444141, 0x2d2b2b,
    ]
    private static let accentRamp = [
        0xe9f8ff, 0xcbeeff, 0x99e0ff, 0x62c5ee, 0x38a6cf,
        0x1186ac, 0x006786, 0x004961, 0x0a303e,
    ]
    private static let accent2Ramp = [
        0xfff1f4, 0xffdee6, 0xffc0d0, 0xff90b1, 0xff458e,
        0xd82071, 0xaa0b56, 0x790e3d, 0x4b1528,
    ]

    /// A ramp step, 100–900. In dark mode the ramp is read from the other end,
    /// so the same step keeps its role: light fills stay light against the
    /// ground, dark text stays readable on them.
    private static func step(_ ramp: [Int], _ value: Int) -> Color {
        let index = max(0, min(8, value / 100 - 1))
        return dynamic(light: ramp[index], dark: ramp[8 - index])
    }

    static func neutral(_ value: Int) -> Color { step(neutralRamp, value) }
    static func accentStep(_ value: Int) -> Color { step(accentRamp, value) }
    static func accent2Step(_ value: Int) -> Color { step(accent2Ramp, value) }

    // MARK: Roles

    static let bg = dynamic(light: 0xf3f2f2, dark: 0x201e1d)
    static let surface = dynamic(light: 0xeae9e9, dark: 0x2d2b2b)
    static let text = dynamic(light: 0x201e1d, dark: 0xf3f2f2)
    /// Cyan: every interactive element.
    static let accent = dynamic(light: 0x0088b0, dark: 0x62c5ee)
    /// Magenta: the rarer second spot colour — critiques, flags, disagreements.
    static let accent2 = dynamic(light: 0xd6006c, dark: 0xff90b1)
    /// Paragraph-size accent text needs a deep step on paper (readme).
    static let accentText = dynamic(light: 0x006786, dark: 0x99e0ff)
    static let accent2Text = dynamic(light: 0xaa0b56, dark: 0xffc0d0)

    static let divider = text.opacity(0.16)
    static let muted = text.opacity(0.55)
    static let secondary = text.opacity(0.72)

    /// NFR-9: photographs sit on neutral grey in both appearances.
    static let photoGround = Color(nsColor: NSColor(calibratedWhite: 0.36, alpha: 1))

    // MARK: Spacing (density 1.25×, from the token sheet)

    enum Space {
        static let one: CGFloat = 5
        static let two: CGFloat = 10
        static let three: CGFloat = 15
        static let four: CGFloat = 20
        static let six: CGFloat = 30
        static let eight: CGFloat = 40
    }

    static let radius: CGFloat = 2

    // MARK: Type — Source Serif 4, or the system serif when it is not installed

    private static let serifName: String? = {
        let candidates = ["Source Serif 4", "SourceSerif4-Regular", "Source Serif Pro"]
        return candidates.first { NSFont(name: $0, size: 12) != nil }
    }()

    static func heading(_ size: CGFloat) -> Font {
        if let serifName { return .custom(serifName, fixedSize: size).weight(.semibold) }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    static func body(_ size: CGFloat) -> Font {
        if let serifName { return .custom(serifName, fixedSize: size) }
        return .system(size: size, design: .serif)
    }

    static func italic(_ size: CGFloat) -> Font { body(size).italic() }

    /// The small uppercase label the wireframes use above every block.
    static func kicker() -> Font { heading(11) }

    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

    // MARK: Helpers

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

// MARK: - Shared small views

/// The uppercase section label used throughout the wireframes.
struct Kicker: View {
    let text: String
    var tint: Color = Broadsheet.muted

    init(_ text: String, tint: Color = Broadsheet.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(Broadsheet.kicker())
            .tracking(1)
            .foregroundStyle(tint)
    }
}

enum TagStyle {
    case accent, accent2, neutral, outline
}

struct TagLabel: View {
    let text: String
    var style: TagStyle = .neutral

    init(_ text: String, style: TagStyle = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(Broadsheet.body(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(background)
            .foregroundStyle(foreground)
            .overlay {
                if case .outline = style {
                    RoundedRectangle(cornerRadius: Broadsheet.radius)
                        .stroke(Broadsheet.accent, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Broadsheet.radius))
    }

    private var background: Color {
        switch style {
        case .accent: return Broadsheet.accentStep(100)
        case .accent2: return Broadsheet.accent2Step(100)
        case .neutral: return Broadsheet.neutral(100)
        case .outline: return .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .accent: return Broadsheet.accentStep(800)
        case .accent2: return Broadsheet.accent2Step(800)
        case .neutral: return Broadsheet.neutral(800)
        case .outline: return Broadsheet.accent
        }
    }
}

/// A label-and-value grid, the wireframes' way of showing photo and
/// competition facts.
struct FactRows: View {
    let rows: [(String, String)]
    var valueFont: Font = Broadsheet.body(14)

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Broadsheet.Space.four, verticalSpacing: 4) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    Text(rows[index].0)
                        .font(Broadsheet.body(14))
                        .foregroundStyle(Broadsheet.muted)
                        .gridColumnAlignment(.leading)
                    Text(rows[index].1)
                        .font(valueFont)
                        .foregroundStyle(Broadsheet.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Istvan's rating as the five boxes from the wireframes (DET-2).
struct RatingBoxes: View {
    let rating: Int?
    var size: CGFloat = 36
    var onRate: ((Int?) -> Void)?

    var body: some View {
        HStack(spacing: Broadsheet.Space.one) {
            ForEach(1...5, id: \.self) { value in
                let isOn = rating == value
                Text("\(value)")
                    .font(isOn ? Broadsheet.heading(15) : Broadsheet.body(15))
                    .frame(width: size, height: size)
                    .background(isOn ? Broadsheet.accent : Color.clear)
                    .foregroundStyle(isOn ? Broadsheet.bg : Broadsheet.text)
                    .overlay {
                        Rectangle().stroke(isOn ? Broadsheet.accent : Broadsheet.neutral(400), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onRate?(isOn ? nil : value) }
                    .accessibilityLabel("Rate \(value)")
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}

/// The compact star form used on thumbnails and overlays.
struct Stars: View {
    let rating: Int?
    var size: CGFloat = 12
    var tint: Color = Broadsheet.accentText

    var body: some View {
        Text(String(repeating: "★", count: rating ?? 0))
            .font(Broadsheet.body(size))
            .foregroundStyle(tint)
            .accessibilityLabel(rating.map { "My rating \($0)" } ?? "Not rated")
    }
}
