import SwiftUI

/// A compact menu-style selector that matches the rest of the settings UI
/// instead of using the stock macOS pop-up button appearance.
struct FocusSelectMenu<Item: Identifiable & Equatable>: View {
    let options: [Item]
    let selection: Item
    let title: (Item) -> String
    var width: CGFloat
    let onSelect: (Item) -> Void

    var body: some View {
        Menu {
            ForEach(options) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack {
                        Text(title(item))
                        if item == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title(selection))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
