import AppKit
import SwiftUI
import DeepSeekFocusCore

enum FocusTheme {
    static let accent = Color(red: 0.30, green: 0.42, blue: 0.996)
    static let accentDeep = Color(red: 0.20, green: 0.29, blue: 0.86)
    static let warning = Color(red: 0.92, green: 0.48, blue: 0.22)
    static let radiusLarge: CGFloat = 30
    static let radiusSearch: CGFloat = 28

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.36, green: 0.50, blue: 1.0), accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum SpotlightMetrics {
    static let shadowInset: CGFloat = 48
    static let initialVisualWidth: CGFloat = 860
    static let initialVisualHeight: CGFloat = 68
    static let expandedVisualWidth: CGFloat = 900
    static let expandedMaxHeight: CGFloat = 720
    static let expandedTopFraction: CGFloat = 0.075
    static let initialTopFraction: CGFloat = 0.185
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct FocusPanelBackground: View {
    var cornerRadius: CGFloat
    var prominentShadow = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if !reduceTransparency {
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
            }
            Color(nsColor: .windowBackgroundColor)
                .opacity(reduceTransparency ? 1 : (colorScheme == .dark ? 0.94 : 0.92))
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                Color.primary.opacity(colorScheme == .dark ? 0.24 : 0.16),
                lineWidth: 0.95
            )
        }
        .overlay {
            shape.inset(by: 1.0)
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.46),
                    lineWidth: 0.75
                )
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark
                                  ? (prominentShadow ? 0.30 : 0.26)
                                  : (prominentShadow ? 0.10 : 0.06)),
            radius: prominentShadow ? 3 : 2,
            x: 0,
            y: 1
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark
                                  ? (prominentShadow ? 0.40 : 0.34)
                                  : (prominentShadow ? 0.20 : 0.14)),
            radius: prominentShadow ? 16 : 10,
            x: 0,
            y: prominentShadow ? 6 : 4
        )
    }
}

struct FocusAvatar: View {
    var size: CGFloat
    var showsBackground = true

    var body: some View {
        Group {
            if let image = DeepSeekAssets.mark {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                        .fill(FocusTheme.accentGradient)
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showsBackground {
                RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.7)
            }
        }
        .shadow(color: .black.opacity(0.13), radius: 3, x: 0, y: 1.5)
    }
}

enum DeepSeekAssets {
    static let mark: NSImage? = {
        if let url = Bundle.main.url(forResource: "DeepSeekMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        let candidates = [
            FileManager.default.currentDirectoryPath + "/Resources/DeepSeekMark.png",
            FileManager.default.currentDirectoryPath + "/deepseek-focus/Resources/DeepSeekMark.png"
        ]
        for path in candidates {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }()
}

struct FocusIconButton: View {
    let systemName: String
    var help: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 12.5
    var iconOffset: CGSize = .zero
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(hovering ? 0.95 : 0.70))
                .offset(x: iconOffset.width, y: iconOffset.height)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(Color.white.opacity(hovering ? (colorScheme == .dark ? 0.12 : 0.44) : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L10n.string(help))
        .accessibilityLabel(L10n.string(help))
    }
}

struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(FocusTheme.accent.opacity(0.65))
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 1 : 0.35)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.13),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

struct DividerLine: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.095))
            .frame(height: 0.75)
    }
}

extension View {
    func focusCard(cornerRadius: CGFloat = 14) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.042))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.7)
                }
        }
    }
}

extension View {
    @ViewBuilder
    func withoutFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
