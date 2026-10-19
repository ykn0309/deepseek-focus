import AppKit
import Carbon.HIToolbox
import DeepSeekFocusCore

final class HotKeyManager {
    var onHotKey: (() -> Void)?
    var onSecondaryHotKey: (() -> Void)?

    private struct Registration {
        var ref: EventHotKeyRef
        var shortcut: AppShortcut
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType

    init(signature: OSType = 0x44534643, onHotKey: (() -> Void)? = nil) {
        self.signature = signature
        self.onHotKey = onHotKey
        installEventHandler()
    }

    deinit {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func register(_ shortcut: AppShortcut, id: UInt32 = 1) -> String? {
        if let existing = registrations[id],
           existing.shortcut.keyCode == shortcut.keyCode,
           existing.shortcut.modifiers == shortcut.modifiers {
            return nil
        }
        guard shortcut.isValid else {
            return L10n.string("这个快捷键无效，请至少使用一个修饰键（⌘、⌥、⌃），或选择功能键。")
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
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

        if let existing = registrations[id] {
            UnregisterEventHotKey(existing.ref)
        }
        registrations[id] = Registration(ref: newRef, shortcut: shortcut)
        return nil
    }

    func unregister(id: UInt32 = 1) {
        if let existing = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(existing.ref)
        }
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
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
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
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
                    return OSStatus(eventNotHandledErr)
                }
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    if id == 1 {
                        manager.onHotKey?()
                    } else if id == 2 {
                        manager.onSecondaryHotKey?()
                    }
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
