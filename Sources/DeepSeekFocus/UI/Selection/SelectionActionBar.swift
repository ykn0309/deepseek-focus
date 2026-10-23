import SwiftUI
import DeepSeekFocusCore

struct SelectionActionBar: View {
    var onSelect: (SelectionAction) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            SelectionBarButton(title: "问 DeepSeek", primary: true) { onSelect(.ask) }
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1, height: 12)
                .padding(.horizontal, 3)
                .accessibilityHidden(true)
            SelectionBarButton(title: "翻译") { onSelect(.translate) }
            SelectionBarButton(title: "查词") { onSelect(.dictionary) }
        }
        .padding(4)
        .background(Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 0.5)
        }
        .fixedSize()
    }
}

private struct SelectionBarButton: View {
    let title: LocalizedStringKey
    var primary = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: primary ? .medium : .regular))
                .foregroundStyle(primary ? FocusTheme.accent : Color.primary.opacity(0.85))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.primary.opacity(isHovering ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .withoutFocusRing()
        .onHover { isHovering = $0 }
    }
}
