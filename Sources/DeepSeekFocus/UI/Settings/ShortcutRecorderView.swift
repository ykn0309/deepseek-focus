import AppKit
import SwiftUI
import DeepSeekFocusCore

struct ShortcutSettingRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let shortcut: AppShortcut
    let error: String?
    let onApply: (AppShortcut) -> Bool
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 11.5, weight: .medium))
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                Text(isRecording ? L10n.string("请按下新的快捷键…") : shortcut.displayString)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(isRecording ? FocusTheme.accent : .primary.opacity(0.86))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(minWidth: 100, alignment: .center)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(isRecording ? 0.035 : 0.055))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        isRecording ? FocusTheme.accent.opacity(0.45) : Color.primary.opacity(0.09),
                                        lineWidth: isRecording ? 1.2 : 0.7
                                    )
                            }
                    }

                if isRecording {
                    ThinkingDots()
                }

                Button(L10n.string("恢复默认")) {
                    stopRecording()
                    onReset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording ? L10n.string("取消") : L10n.string("录制"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isRecording ? FocusTheme.accent : .primary.opacity(0.72))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(isRecording
                 ? L10n.string("按下带有 ⌘、⌥ 或 ⌃ 的组合键，按 Esc 取消。")
                 : L10n.string("点击「录制」设置快捷键，建议使用未与系统冲突的组合。"))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(FocusTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            guard let shortcut = AppShortcut.from(event: event) else {
                NSSound.beep()
                return nil
            }
            if !onApply(shortcut) {
                NSSound.beep()
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
