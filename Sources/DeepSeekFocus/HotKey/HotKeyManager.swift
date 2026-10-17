import AppKit
import Carbon.HIToolbox
import DeepSeekFocusCore

final class HotKeyManager {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var registeredShortcut: AppShortcut?
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x44534643 // "DSFC"

    init(onHotKey: (() -> Void)? = nil) {
        self.onHotKey = onHotKey
        installEventHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func register(_ shortcut: AppShortcut) -> String? {
        if shortcutsEqual(registeredShortcut, shortcut), hotKeyRef != nil {
            return nil
        }
        guard shortcut.isValid else {
            return L10n.string("这个快捷键无效，请至少使用一个修饰键（⌘、⌥、⌃），或选择功能键。")
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: nextID)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else {
            return L10n.format("无法注册 %@。它可能已被其他应用或系统占用（%ld）。", shortcut.displayString, status)
        }

        if let oldRef = hotKeyRef {
            UnregisterEventHotKey(oldRef)
        }
        hotKeyRef = newRef
        registeredShortcut = shortcut
        nextID &+= 1
        return nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredShortcut = nil
    }

    private func shortcutsEqual(_ lhs: AppShortcut?, _ rhs: AppShortcut) -> Bool {
        guard let lhs else { return false }
        return lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == manager.signature else {
                    return noErr
                }
                DispatchQueue.main.async {
                    manager.onHotKey?()
                }
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandler
        )
    }
}
