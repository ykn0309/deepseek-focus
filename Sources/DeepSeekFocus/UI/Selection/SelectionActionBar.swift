import SwiftUI
import DeepSeekFocusCore

struct SelectionActionBar: View {
    var onSelect: (SelectionAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            SelectionBarButton(
                title: "问 DeepSeek",
                icon: "sparkles",
                action: { onSelect(.ask) }
            )

            Divider()
                .frame(height: 14)
                .opacity(0.55)

            SelectionBarButton(
                title: "翻译",
                icon: "character.bubble",
                action: { onSelect(.translate) }
            )
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .fixedSize()
    }
}

private struct SelectionBarButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color.primary.opacity(isHovering ? 0.075 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
