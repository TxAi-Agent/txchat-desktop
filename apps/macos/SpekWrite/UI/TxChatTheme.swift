import AppKit
import CoreText
import SwiftUI

enum TxChatTheme {
    enum Palette {
        static let canvas = adaptive(
            light: NSColor(srgbRed: 251 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1),
            dark: NSColor(srgbRed: 28 / 255, green: 27 / 255, blue: 26 / 255, alpha: 1)
        )
        static let raised = adaptive(
            light: NSColor(srgbRed: 1, green: 252 / 255, blue: 248 / 255, alpha: 1),
            dark: NSColor(srgbRed: 42 / 255, green: 40 / 255, blue: 38 / 255, alpha: 1)
        )
        static let nodeSurface = raised
        static let primaryText = adaptive(
            light: NSColor(srgbRed: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1),
            dark: NSColor(srgbRed: 240 / 255, green: 238 / 255, blue: 235 / 255, alpha: 1)
        )
        static let secondaryText = adaptive(
            light: NSColor(srgbRed: 112 / 255, green: 112 / 255, blue: 112 / 255, alpha: 1),
            dark: NSColor(srgbRed: 154 / 255, green: 149 / 255, blue: 144 / 255, alpha: 1)
        )
        static let tertiaryText = adaptive(
            light: NSColor(srgbRed: 119 / 255, green: 113 / 255, blue: 107 / 255, alpha: 1),
            dark: NSColor(srgbRed: 138 / 255, green: 133 / 255, blue: 128 / 255, alpha: 1)
        )
        static let warmAccent = Color(
            red: 0.788,
            green: 0.584,
            blue: 0.475
        )
        static let warmLine = Color(
            red: 0.76,
            green: 0.48,
            blue: 0.34
        )
        static let success = Color(
            red: 49 / 255,
            green: 168 / 255,
            blue: 83 / 255
        )
        static let warningLight = NSColor(
            srgbRed: 199 / 255,
            green: 125 / 255,
            blue: 41 / 255,
            alpha: 1
        )
        static let warningDark = NSColor(
            srgbRed: 214 / 255,
            green: 148 / 255,
            blue: 80 / 255,
            alpha: 1
        )
        static let warning = adaptive(light: warningLight, dark: warningDark)
        static let smsStatusIconLight = NSColor(
            srgbRed: 180 / 255,
            green: 106 / 255,
            blue: 31 / 255,
            alpha: 1
        )
        static let smsStatusIconDark = NSColor(
            srgbRed: 214 / 255,
            green: 148 / 255,
            blue: 80 / 255,
            alpha: 1
        )
        static let smsStatusIcon = adaptive(
            light: smsStatusIconLight,
            dark: smsStatusIconDark
        )
        static let error = Color(
            red: 184 / 255,
            green: 41 / 255,
            blue: 36 / 255
        )
        static let dictionaryDanger = Color(
            red: 201 / 255,
            green: 74 / 255,
            blue: 69 / 255
        )
        static let border = adaptive(
            light: NSColor(srgbRed: 222 / 255, green: 216 / 255, blue: 208 / 255, alpha: 1),
            dark: NSColor(srgbRed: 66 / 255, green: 63 / 255, blue: 59 / 255, alpha: 1)
        )
        static let controlBorder = adaptive(
            light: NSColor(srgbRed: 207 / 255, green: 199 / 255, blue: 191 / 255, alpha: 1),
            dark: NSColor(srgbRed: 74 / 255, green: 70 / 255, blue: 67 / 255, alpha: 1)
        )
        static let fieldBorder = adaptive(
            light: NSColor(srgbRed: 227 / 255, green: 221 / 255, blue: 214 / 255, alpha: 1),
            dark: NSColor(srgbRed: 61 / 255, green: 58 / 255, blue: 53 / 255, alpha: 1)
        )
        static let fieldInset = adaptive(
            light: NSColor(srgbRed: 245 / 255, green: 241 / 255, blue: 236 / 255, alpha: 1),
            dark: NSColor(srgbRed: 46 / 255, green: 44 / 255, blue: 41 / 255, alpha: 1)
        )
        static let fieldAction = adaptive(
            light: NSColor(srgbRed: 240 / 255, green: 235 / 255, blue: 227 / 255, alpha: 1),
            dark: NSColor(srgbRed: 58 / 255, green: 54 / 255, blue: 51 / 255, alpha: 1)
        )
        static let fieldFocus = Color(
            red: 0.73,
            green: 0.54,
            blue: 0.43
        )
        static let fieldError = Color(
            red: 0.91,
            green: 0.42,
            blue: 0.34
        )
        static let fieldActionText = adaptive(
            light: NSColor(srgbRed: 139 / 255, green: 96 / 255, blue: 74 / 255, alpha: 1),
            dark: NSColor(srgbRed: 218 / 255, green: 177 / 255, blue: 156 / 255, alpha: 1)
        )
        static let permissionBorder = adaptive(
            light: NSColor(srgbRed: 222 / 255, green: 212 / 255, blue: 201 / 255, alpha: 1),
            dark: NSColor(srgbRed: 66 / 255, green: 63 / 255, blue: 59 / 255, alpha: 1)
        )
        static let disabledControl = adaptive(
            light: NSColor(srgbRed: 199 / 255, green: 194 / 255, blue: 186 / 255, alpha: 0.72),
            dark: NSColor(srgbRed: 92 / 255, green: 88 / 255, blue: 84 / 255, alpha: 0.72)
        )
        static let keycap = Color(
            red: 23 / 255,
            green: 22 / 255,
            blue: 21 / 255
        )
        static let inverseSurfaceLight = NSColor(
            srgbRed: 23 / 255,
            green: 22 / 255,
            blue: 21 / 255,
            alpha: 1
        )
        static let inverseSurfaceDark = NSColor(
            srgbRed: 255 / 255,
            green: 252 / 255,
            blue: 248 / 255,
            alpha: 1
        )
        static let inverseTextLight = NSColor(
            srgbRed: 251 / 255,
            green: 250 / 255,
            blue: 248 / 255,
            alpha: 1
        )
        static let inverseTextDark = NSColor(
            srgbRed: 17 / 255,
            green: 17 / 255,
            blue: 17 / 255,
            alpha: 1
        )
        static let inverseSurface = adaptive(
            light: inverseSurfaceLight,
            dark: inverseSurfaceDark
        )
        static let inverseText = adaptive(
            light: inverseTextLight,
            dark: inverseTextDark
        )
        static let primaryControl = adaptive(
            light: NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 17 / 255, alpha: 1),
            dark: NSColor(srgbRed: 240 / 255, green: 238 / 255, blue: 235 / 255, alpha: 1)
        )
        static let onPrimaryControl = adaptive(
            light: NSColor(srgbRed: 251 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1),
            dark: NSColor(srgbRed: 28 / 255, green: 27 / 255, blue: 26 / 255, alpha: 1)
        )
        static let blueLink = Color(red: 10 / 255, green: 132 / 255, blue: 1)

        private static func adaptive(light: NSColor, dark: NSColor) -> Color {
            Color(
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? dark
                        : light
                }
            )
        }
    }

    enum Spacing {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 36
        static let xxLarge: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 8
        static let control: CGFloat = 12
        static let field: CGFloat = 13
        static let panel: CGFloat = 20
        static let keycap: CGFloat = 14
    }

    enum Layout {
        static let windowWidth: CGFloat = 720
        static let windowHeight: CGFloat = 560
        static let windowTitlebarHeight: CGFloat = 32
        static let windowContentHeight = windowHeight - windowTitlebarHeight
        static let windowRadius: CGFloat = 16
        static let homeContentX: CGFloat = 197
        static let statusSpineX: CGFloat = 37
        static let largeKeycapHeight: CGFloat = 80
        static let inlineKeycapHeight: CGFloat = 28
        static let modeWidth: CGFloat = 180
        static let modeHeight: CGFloat = 36
        static let contentInset: CGFloat = 38
        static let statusWidth: CGFloat = 132
        static let keycapSize: CGFloat = largeKeycapHeight
        static let formWidth: CGFloat = 286
        static let menuWidth: CGFloat = 360
        static let menuHeight: CGFloat = 220
        static let hudLogoSize: CGFloat = 56
        static let shortcutEditorWidth: CGFloat = 520
        static let shortcutEditorHeight: CGFloat = 387
        static let shortcutSecondaryButtonWidth: CGFloat = 64
        static let shortcutSecondaryButtonHeight: CGFloat = 43
        static let shortcutPrimaryButtonWidth: CGFloat = 62
        static let shortcutRetryButtonWidth: CGFloat = 88
        static let shortcutPrimaryButtonHeight: CGFloat = 41
    }

    static let loginDisplay = noto(38, weight: .bold)
    static let headline = noto(36, weight: .bold)
    static let title = noto(28, weight: .bold)
    static let readerTitle = noto(23, weight: .bold)
    static let readerHeading = noto(15, weight: .medium)
    static let readerBody = noto(14)
    static let bodyEmphasis = noto(17, weight: .medium)
    static let dialogBody = noto(16)
    static let bodyControl = noto(15, weight: .medium)
    static let body = noto(15)
    static let compactBody = noto(14)
    static let status = noto(13)
    static let hudLabel = noto(13, weight: .medium)
    static let hudCaption = noto(11)
    static let hudAction = noto(12, weight: .medium)
    static let control = noto(13, weight: .medium)
    static let label = noto(14, weight: .medium)
    static let caption = noto(12)
    static let compactCaption = noto(11)

    static func noto(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        Font.custom(postScriptName(for: weight), fixedSize: size)
    }

    private static func postScriptName(
        for weight: Font.Weight
    ) -> String {
        if weight == .black || weight == .heavy || weight == .bold {
            return "NotoSansSC-Bold"
        }
        if weight == .semibold || weight == .medium {
            return "NotoSansSC-Medium"
        }
        return "NotoSansSC-Regular"
    }
}

enum TxChatFontRegistry {
    enum RegistrationError: Error {
        case resourceMissing
        case registrationFailed(CFError?)
    }

    @MainActor
    static func registerBundledFont(
        bundle: Bundle = .main
    ) throws -> Bool {
        if NSFont(name: "NotoSansSC-Regular", size: 15) != nil {
            return true
        }
        guard let url = bundle.url(
            forResource: "NotoSansSC-VF",
            withExtension: "ttf"
        ) else {
            throw RegistrationError.resourceMissing
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &error
        )
        guard registered ||
            NSFont(name: "NotoSansSC-Regular", size: 15) != nil
        else {
            throw RegistrationError.registrationFailed(
                error?.takeRetainedValue()
            )
        }
        return true
    }
}

struct TxChatBrandMark: View {
    var size: CGFloat = 64
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("TxChatLogoSymbol")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("TxChat")
            .accessibilityValue(colorScheme == .dark ? "Dark" : "Light")
    }
}

struct TxChatHeaderBrandLockup: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            TxChatBrandMark(size: 56)

            Image("TxChatHeaderWordmark")
                .resizable()
                .frame(width: 97.183, height: 22)
                .offset(x: 62, y: 17)
        }
        .frame(
            width: 159.183,
            height: 56,
            alignment: .topLeading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TxChat")
        .accessibilityValue(colorScheme == .dark ? "Dark" : "Light")
    }
}

struct TxChatPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.label)
            .foregroundStyle(TxChatTheme.Palette.onPrimaryControl)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                TxChatTheme.Palette.primaryControl.opacity(
                    configuration.isPressed ? 0.78 : 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: TxChatTheme.Radius.control,
                    style: .continuous
                )
            )
    }
}

struct TxChatSecondaryButtonStyle: ButtonStyle {
    var fixedWidth: CGFloat?
    var fixedHeight: CGFloat

    init(
        fixedWidth: CGFloat? = nil,
        fixedHeight: CGFloat = 40
    ) {
        self.fixedWidth = fixedWidth
        self.fixedHeight = fixedHeight
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TxChatTheme.label)
            .foregroundStyle(TxChatTheme.Palette.primaryText)
            .padding(.horizontal, 15)
            .frame(width: fixedWidth, height: fixedHeight)
            .background(
                TxChatTheme.Palette.raised.opacity(
                    configuration.isPressed ? 0.65 : 1
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TxChatTheme.Radius.control,
                    style: .continuous
                )
                .stroke(TxChatTheme.Palette.border)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: TxChatTheme.Radius.control,
                    style: .continuous
                )
            )
    }
}
