import SwiftUI

// Design tokens (README "Design tokens"). Later phases append tokens at the end of the relevant enum only.
enum OT {
    enum C {
        static let notch = Color(hex: 0x000000)
        static let raised = Color(hex: 0x1C1C1E)
        static let diffCard = Color(hex: 0x141416)
        static let terminal = Color(hex: 0x0B0B0C)
        static let selected = Color(hex: 0x2C2C2E)
        static let selected2 = Color(hex: 0x3A3A3C)
        static let divider = Color(hex: 0x1C1C1E)
        static let divider2 = Color(hex: 0x2C2C2E)
        static let text = Color(hex: 0xFFFFFF)
        static let text1 = Color(hex: 0xE5E5EA)
        static let text2 = Color(hex: 0xD1D1D6)
        static let text3 = Color(hex: 0xC4C4C6)
        static let text4 = Color(hex: 0xAEAEB2)
        static let text5 = Color(hex: 0x8E8E93)
        static let text6 = Color(hex: 0x636366)
        static let claude = Color(hex: 0xD97757)
        static let green = Color(hex: 0x30D158)
        static let orange = Color(hex: 0xFF9F0A)
        static let orangeText = Color(hex: 0xFFB35C)
        static let orangeBg = Color(hex: 0x3A2410)
        static let red = Color(hex: 0xFF453A)
        static let redText = Color(hex: 0xFF6961)
        static let redBg = Color(hex: 0x2A1A19)
    }
    enum F {
        static let title = Font.system(size: 14, weight: .semibold)
        static let stateTitle = Font.system(size: 14, weight: .medium)
        static let prose = Font.system(size: 13)
        static let ui = Font.system(size: 12)
        static let uiMedium = Font.system(size: 12, weight: .medium)
        static let meta = Font.system(size: 11)
        static let hint = Font.system(size: 10)
        static let tiny = Font.system(size: 9)
        static let monoCommand = Font.system(size: 12, design: .monospaced)
        static let monoPath = Font.system(size: 11, design: .monospaced)
        static let monoChip = Font.system(size: 10, design: .monospaced)
    }
    enum R {
        static let notchOpen: CGFloat = 24
        static let notchExpanded: CGFloat = 26
        static let dropdown: CGFloat = 22
        static let notchClosed: CGFloat = 12
        static let cardL: CGFloat = 12
        static let cardM: CGFloat = 10
        static let cardS: CGFloat = 9
        static let pill30: CGFloat = 15
        static let pill28: CGFloat = 14
        static let keycap: CGFloat = 4
        static let approvalPanel: CGFloat = 22
    }
    enum S {
        static let header: CGFloat = 34
        static let padTop: CGFloat = 0
        static let padH: CGFloat = 14
        static let padBottom: CGFloat = 12
        static let gapS: CGFloat = 5
        static let gapL: CGFloat = 9
    }
}

fileprivate extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
