import Carbon
import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys via Carbon `RegisterEventHotKey`.
final class HotkeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var idToAction: [UInt32: SnapAction] = [:]
    private let onAction: (SnapAction) -> Void
    private let onShowLayouts: (() -> Void)?
    private let layoutsHotKeyID: UInt32 = 100
    private var lastEventTime: UInt64 = 0

    init(
        onAction: @escaping (SnapAction) -> Void,
        onShowLayouts: (() -> Void)? = nil
    ) {
        self.onAction = onAction
        self.onShowLayouts = onShowLayouts
    }

    deinit {
        unregister()
    }

    func register() {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(event: event)
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        guard status == noErr else {
            NSLog("PaneKit: InstallEventHandler failed: \(status)")
            return
        }

        registerSnapHotkeys()
        registerLayoutsHotkey()
    }

    /// Re-read custom shortcuts from preferences and re-register.
    func reload() {
        // Keep the event handler; only refresh hotkey refs.
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        idToAction.removeAll()
        registerSnapHotkeys()
        registerLayoutsHotkey()
    }

    /// Temporarily unregister while recording a new shortcut.
    func pause() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        idToAction.removeAll()
    }

    func resume() {
        registerSnapHotkeys()
        registerLayoutsHotkey()
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        idToAction.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func registerSnapHotkeys() {
        for def in HotkeyDefinition.resolved() where def.isEnabled {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: FourCharCode("PKit"), id: def.id)
            let registerStatus = RegisterEventHotKey(
                def.keyCode,
                def.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if registerStatus == noErr {
                hotKeyRefs.append(hotKeyRef)
                idToAction[def.id] = def.action
            } else {
                NSLog("PaneKit: RegisterEventHotKey failed for \(def.action.rawValue): \(registerStatus)")
            }
        }
    }

    private func registerLayoutsHotkey() {
        guard onShowLayouts != nil else { return }
        var layoutsRef: EventHotKeyRef?
        let layoutsID = EventHotKeyID(signature: FourCharCode("PKit"), id: layoutsHotKeyID)
        let layoutsStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(controlKey | optionKey),
            layoutsID,
            GetApplicationEventTarget(),
            0,
            &layoutsRef
        )
        if layoutsStatus == noErr {
            hotKeyRefs.append(layoutsRef)
        } else {
            NSLog("PaneKit: RegisterEventHotKey failed for layouts: \(layoutsStatus)")
        }
    }

    private func handle(event: EventRef?) -> OSStatus {
        guard let event else { return noErr }
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
        guard status == noErr else { return noErr }

        let now = DispatchTime.now().uptimeNanoseconds
        if now &- lastEventTime < 50_000_000 { return noErr }
        lastEventTime = now

        if hotKeyID.id == layoutsHotKeyID {
            DispatchQueue.main.async { [onShowLayouts] in
                onShowLayouts?()
            }
            return noErr
        }

        guard let action = idToAction[hotKeyID.id] else {
            return noErr
        }
        DispatchQueue.main.async { [onAction] in
            onAction(action)
        }
        return noErr
    }
}

private extension FourCharCode {
    init(_ string: String) {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        self = result
    }
}
