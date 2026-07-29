import SwiftUI

/// Visual styling for Paydirt's native feedback presentation.
///
/// Use ``automatic`` to inherit semantic iOS light and dark colors, or provide
/// brand colors that match the host application. The automatic preset follows
/// the host color scheme; `preferredColorScheme` can optionally select one.
public struct PaydirtTheme {
    public var background: Color
    public var surface: Color
    public var primaryText: Color
    public var secondaryText: Color
    public var accent: Color
    public var accentText: Color
    public var border: Color
    public var error: Color
    public var overlay: Color
    public var overlayText: Color
    public var preferredColorScheme: ColorScheme?
    public var cornerRadius: CGFloat

    public init(
        background: Color = Color(uiColor: .systemBackground),
        surface: Color = Color(uiColor: .secondarySystemBackground),
        primaryText: Color = Color(uiColor: .label),
        secondaryText: Color = Color(uiColor: .secondaryLabel),
        accent: Color = Color(uiColor: .label),
        accentText: Color = Color(uiColor: .systemBackground),
        border: Color = Color(uiColor: .separator),
        error: Color = Color(uiColor: .systemRed),
        overlay: Color = Color.black.opacity(0.4),
        overlayText: Color = .white,
        preferredColorScheme: ColorScheme? = nil,
        cornerRadius: CGFloat = 20
    ) {
        self.background = background
        self.surface = surface
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accent = accent
        self.accentText = accentText
        self.border = border
        self.error = error
        self.overlay = overlay
        self.overlayText = overlayText
        self.preferredColorScheme = preferredColorScheme
        self.cornerRadius = cornerRadius
    }

    /// Semantic iOS colors that automatically follow the host app's appearance.
    public static let automatic = PaydirtTheme(
        background: Color(uiColor: .systemBackground),
        surface: Color(uiColor: .secondarySystemBackground),
        primaryText: Color(uiColor: .label),
        secondaryText: Color(uiColor: .secondaryLabel),
        accent: Color(uiColor: .label),
        accentText: Color(uiColor: .systemBackground),
        border: Color(uiColor: .separator)
    )

    public static let light = PaydirtTheme(
        background: .white,
        surface: Color(uiColor: .secondarySystemBackground),
        primaryText: .black,
        secondaryText: .gray,
        accent: .black,
        accentText: .white,
        border: Color.black.opacity(0.16),
        preferredColorScheme: .light
    )

    public static let dark = PaydirtTheme(
        background: Color(uiColor: .systemBackground),
        surface: Color(uiColor: .secondarySystemBackground),
        primaryText: .white,
        secondaryText: Color(uiColor: .secondaryLabel),
        accent: .white,
        accentText: .black,
        border: Color.white.opacity(0.2),
        preferredColorScheme: .dark
    )
}
