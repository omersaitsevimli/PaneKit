import AppKit
import Carbon
import Carbon.HIToolbox

/// Click-to-record shortcut field used in Preferences → Shortcuts.
final class KeyRecorderView: NSView {
    var onRecorded: ((UInt32, UInt32) -> Void)?
    var onConflict: ((SnapAction) -> Void)?
    /// Called so the host can pause/resume global hotkeys while recording.
    var onRecordingChanged: ((Bool) -> Void)?

    private var isRecording = false
    private var displayLabel: NSTextField!
    private var clearButton: NSButton!

    private(set) var currentModifiers: UInt32 = 0
    private(set) var currentKeyCode: UInt32 = 0
    /// Action being edited — excluded from conflict checks.
    var editingAction: SnapAction?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 6

        displayLabel = NSTextField(labelWithString: "")
        displayLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayLabel)

        clearButton = NSButton(title: "✕", target: self, action: #selector(clearShortcut))
        clearButton.bezelStyle = .inline
        clearButton.font = .systemFont(ofSize: 10)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            displayLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            displayLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setShortcut(modifiers: UInt32, keyCode: UInt32) {
        currentModifiers = modifiers
        currentKeyCode = keyCode
        let isDisabled = modifiers == 0 || keyCode == 0
        displayLabel.stringValue = isDisabled
            ? ""
            : ShortcutFormatter.displayString(modifiers: modifiers, keyCode: keyCode)
        clearButton.isHidden = isDisabled
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return }

        let keyCode = UInt32(event.keyCode)
        if modifiers == currentModifiers, keyCode == currentKeyCode {
            stopRecording()
            return
        }

        for action in SnapAction.allCases where action != editingAction {
            let existing = UserPreferences.shared.hotkey(for: action)
            guard existing.modifiers != 0, existing.keyCode != 0 else { continue }
            if existing.modifiers == modifiers && existing.keyCode == keyCode {
                onConflict?(action)
                stopRecording()
                return
            }
        }

        currentModifiers = modifiers
        currentKeyCode = keyCode
        displayLabel.stringValue = ShortcutFormatter.displayString(modifiers: modifiers, keyCode: keyCode)
        clearButton.isHidden = false
        stopRecording()
        onRecorded?(modifiers, keyCode)
    }

    override var acceptsFirstResponder: Bool { true }

    private func startRecording() {
        isRecording = true
        onRecordingChanged?(true)
        displayLabel.stringValue = "Kısayol yazın… / Type shortcut…"
        displayLabel.font = .systemFont(ofSize: 11)
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        isRecording = false
        displayLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        if currentModifiers == 0 || currentKeyCode == 0 {
            displayLabel.stringValue = ""
        } else {
            displayLabel.stringValue = ShortcutFormatter.displayString(
                modifiers: currentModifiers,
                keyCode: currentKeyCode
            )
        }
        onRecordingChanged?(false)
    }

    @objc private func clearShortcut() {
        currentModifiers = 0
        currentKeyCode = 0
        displayLabel.stringValue = ""
        clearButton.isHidden = true
        onRecorded?(0, 0)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
