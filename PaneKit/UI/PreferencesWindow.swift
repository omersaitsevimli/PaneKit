import AppKit
import ServiceManagement

/// Settings window: General + Shortcuts tabs.
final class PreferencesWindowController: NSWindowController {
    private var tabView: NSTabView!
    private let onHotkeysChanged: () -> Void
    private let onDragSnapChanged: () -> Void
    private let onPinPreferencesChanged: () -> Void
    private weak var hotkeyManager: HotkeyManager?

    init(
        hotkeyManager: HotkeyManager?,
        onHotkeysChanged: @escaping () -> Void,
        onDragSnapChanged: @escaping () -> Void,
        onPinPreferencesChanged: @escaping () -> Void = {}
    ) {
        self.hotkeyManager = hotkeyManager
        self.onHotkeysChanged = onHotkeysChanged
        self.onDragSnapChanged = onDragSnapChanged
        self.onPinPreferencesChanged = onPinPreferencesChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PaneKit Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupTabs()
        ensureCloseMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func ensureCloseMenu() {
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = NSMenu()
        }
        let already = NSApp.mainMenu?.items.contains { $0.title == "File" } ?? false
        guard !already else { return }
        let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(closeItem)
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        NSApp.mainMenu?.addItem(fileMenuItem)
    }

    private func setupTabs() {
        guard let content = window?.contentView else { return }
        tabView = NSTabView(frame: content.bounds)
        tabView.autoresizingMask = [.width, .height]

        let general = NSTabViewItem(identifier: "general")
        general.label = "General"
        general.view = makeGeneralView()
        tabView.addTabViewItem(general)

        let shortcuts = NSTabViewItem(identifier: "shortcuts")
        shortcuts.label = "Shortcuts"
        shortcuts.view = makeShortcutsView()
        tabView.addTabViewItem(shortcuts)

        content.addSubview(tabView)
    }

    // MARK: - General

    private func makeGeneralView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))

        var y: CGFloat = 360

        let launch = NSButton(
            checkboxWithTitle: "Açılışta başlat / Launch at Login",
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launch.state = UserPreferences.shared.isLaunchAtLoginEnabled ? .on : .off
        launch.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        if SMAppService.mainApp.status == .requiresApproval {
            launch.toolTip = "Sistem Ayarları → Genel → Açılış Öğeleri’nden PaneKit’e izin verin."
        }
        view.addSubview(launch)
        y -= 28

        let drag = NSButton(
            checkboxWithTitle: "Kenara sürükle (drag-to-snap) / Enable drag-snap",
            target: self,
            action: #selector(toggleDragSnap(_:))
        )
        drag.state = UserPreferences.shared.dragSnapEnabled ? .on : .off
        drag.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        view.addSubview(drag)
        y -= 26

        let split = NSButton(
            checkboxWithTitle: "Ortak kenarı sürükle (büyüt/küçült) / Drag shared edge",
            target: self,
            action: #selector(toggleSplitResize(_:))
        )
        split.state = UserPreferences.shared.splitResizeEnabled ? .on : .off
        split.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        view.addSubview(split)
        y -= 26

        let green = NSButton(
            checkboxWithTitle: "Yeşil düğmenin üstünde ⌥ → Layouts / Option on green button",
            target: self,
            action: #selector(toggleOptionGreenLayouts(_:))
        )
        green.state = UserPreferences.shared.optionGreenButtonLayoutsEnabled ? .on : .off
        green.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        view.addSubview(green)
        y -= 26

        let stage = NSButton(
            checkboxWithTitle: "Stage Manager şeridi için yer bırak / Leave room for Stage Manager",
            target: self,
            action: #selector(toggleStageManagerInset(_:))
        )
        stage.state = UserPreferences.shared.stageManagerInsetEnabled ? .on : .off
        stage.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        view.addSubview(stage)
        y -= 26

        let displayConnect = NSButton(
            checkboxWithTitle: "Ekran bağlanınca workspace yükle / Restore workspace on display connect",
            target: self,
            action: #selector(toggleRestoreOnDisplayConnect(_:))
        )
        displayConnect.state = UserPreferences.shared.restoreWorkspaceOnDisplayConnect ? .on : .off
        displayConnect.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        view.addSubview(displayConnect)
        y -= 26

        let stashReveal = NSButton(
            checkboxWithTitle: "Stash kenarında imleçle göster / Reveal stashed windows on edge hover",
            target: self,
            action: #selector(toggleStashEdgeReveal(_:))
        )
        stashReveal.state = UserPreferences.shared.stashEdgeRevealEnabled ? .on : .off
        stashReveal.frame = NSRect(x: 20, y: y, width: 460, height: 24)
        view.addSubview(stashReveal)
        y -= 34

        let insetLabel = NSTextField(labelWithString: "Neredeyse tam kenar boşluğu / Almost-max inset:")
        insetLabel.frame = NSRect(x: 20, y: y, width: 340, height: 20)
        view.addSubview(insetLabel)
        let insetPopup = NSPopUpButton(frame: NSRect(x: 360, y: y - 4, width: 120, height: 26))
        insetPopup.target = self
        insetPopup.action = #selector(selectAlmostMaximizeInset(_:))
        for value in UserPreferences.almostMaximizeInsetPresets {
            let title = value == UserPreferences.defaultAlmostMaximizeInset
                ? "\(Int(value)) px (default)"
                : "\(Int(value)) px"
            insetPopup.addItem(withTitle: title)
            insetPopup.lastItem?.representedObject = value
            if abs(UserPreferences.shared.almostMaximizeInset - value) < 0.5 {
                insetPopup.select(insetPopup.lastItem)
            }
        }
        view.addSubview(insetPopup)
        y -= 32

        let gapLabel = NSTextField(labelWithString: "Pencere boşluğu / Window gap:")
        gapLabel.frame = NSRect(x: 20, y: y, width: 340, height: 20)
        view.addSubview(gapLabel)
        let gapPopup = NSPopUpButton(frame: NSRect(x: 360, y: y - 4, width: 120, height: 26))
        gapPopup.target = self
        gapPopup.action = #selector(selectWindowGap(_:))
        for value in UserPreferences.windowGapPresets {
            let title = value == UserPreferences.defaultWindowGap
                ? "\(Int(value)) px (default)"
                : "\(Int(value)) px"
            gapPopup.addItem(withTitle: title)
            gapPopup.lastItem?.representedObject = value
            if abs(UserPreferences.shared.windowGap - value) < 0.5 {
                gapPopup.select(gapPopup.lastItem)
            }
        }
        view.addSubview(gapPopup)
        y -= 32

        let pinLabel = NSTextField(labelWithString: "Pin şerit genişliği / Pin sidebar width:")
        pinLabel.frame = NSRect(x: 20, y: y, width: 340, height: 20)
        view.addSubview(pinLabel)
        let pinPopup = NSPopUpButton(frame: NSRect(x: 360, y: y - 4, width: 120, height: 26))
        pinPopup.target = self
        pinPopup.action = #selector(selectPinSidebarWidth(_:))
        for value in UserPreferences.pinSidebarWidthPresets {
            let title = value == UserPreferences.defaultPinSidebarWidth
                ? "\(Int(value)) px (default)"
                : "\(Int(value)) px"
            pinPopup.addItem(withTitle: title)
            pinPopup.lastItem?.representedObject = value
            if abs(UserPreferences.shared.pinSidebarWidth - value) < 0.5 {
                pinPopup.select(pinPopup.lastItem)
            }
        }
        view.addSubview(pinPopup)
        y -= 40

        let hint = NSTextField(wrappingLabelWithString: """
        Kısayolları Shortcuts sekmesinden özelleştirin. Drag-to-snap magnet alanı menü çubuğundan ayarlanır (varsayılan 6 px). Pin Mode menüden açılır; Stage Manager açıksa ana ekranın solundan yer ayrılır. Maximize pencere boşluğunu yok sayar.

        Customize shortcuts in the Shortcuts tab. Enable Pin Mode from the menu bar. Stage Manager inset applies on the main display when Stage Manager is on. Maximize ignores window gap.
        """)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 16, width: 480, height: y - 8)
        view.addSubview(hint)

        return view
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        let enabled = sender.state == .on
        do {
            let status = try UserPreferences.shared.setLaunchAtLogin(enabled)
            if enabled, status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "Login Item Approval Required"
                alert.informativeText = "Allow PaneKit in System Settings → General → Login Items."
                alert.alertStyle = .informational
                alert.runModal()
            }
            sender.state = UserPreferences.shared.isLaunchAtLoginEnabled ? .on : .off
        } catch {
            sender.state = UserPreferences.shared.isLaunchAtLoginEnabled ? .on : .off
            let alert = NSAlert(error: error)
            alert.messageText = "Could Not Update Login Item"
            alert.runModal()
        }
    }

    @objc private func toggleDragSnap(_ sender: NSButton) {
        UserPreferences.shared.dragSnapEnabled = sender.state == .on
        onDragSnapChanged()
    }

    @objc private func toggleSplitResize(_ sender: NSButton) {
        UserPreferences.shared.splitResizeEnabled = sender.state == .on
        onDragSnapChanged()
    }

    @objc private func toggleOptionGreenLayouts(_ sender: NSButton) {
        UserPreferences.shared.optionGreenButtonLayoutsEnabled = sender.state == .on
        onDragSnapChanged()
    }

    @objc private func toggleStageManagerInset(_ sender: NSButton) {
        UserPreferences.shared.stageManagerInsetEnabled = sender.state == .on
        onPinPreferencesChanged()
    }

    @objc private func toggleRestoreOnDisplayConnect(_ sender: NSButton) {
        UserPreferences.shared.restoreWorkspaceOnDisplayConnect = sender.state == .on
    }

    @objc private func toggleStashEdgeReveal(_ sender: NSButton) {
        UserPreferences.shared.stashEdgeRevealEnabled = sender.state == .on
        onDragSnapChanged()
    }

    @objc private func selectAlmostMaximizeInset(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? CGFloat else { return }
        UserPreferences.shared.almostMaximizeInset = value
    }

    @objc private func selectWindowGap(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? CGFloat else { return }
        UserPreferences.shared.windowGap = value
        onPinPreferencesChanged()
    }

    @objc private func selectPinSidebarWidth(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? CGFloat else { return }
        UserPreferences.shared.pinSidebarWidth = value
        onPinPreferencesChanged()
    }

    // MARK: - Shortcuts

    private func makeShortcutsView() -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder

        let actions = SnapAction.allCases
        let rowHeight: CGFloat = 36
        let contentHeight = CGFloat(actions.count) * rowHeight + 24
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: contentHeight))

        for (index, action) in actions.enumerated() {
            let rowY = contentHeight - CGFloat(index + 1) * rowHeight - 4

            let label = NSTextField(labelWithString: "\(action.titleEN)")
            label.toolTip = action.titleTR
            label.frame = NSRect(x: 16, y: rowY, width: 180, height: 24)
            contentView.addSubview(label)

            let recorder = KeyRecorderView(frame: NSRect(x: 200, y: rowY, width: 180, height: 26))
            recorder.identifier = NSUserInterfaceItemIdentifier("recorder-\(index)")
            recorder.editingAction = action
            let hotkey = UserPreferences.shared.hotkey(for: action)
            recorder.setShortcut(modifiers: hotkey.modifiers, keyCode: hotkey.keyCode)
            recorder.onRecordingChanged = { [weak self] recording in
                if recording {
                    self?.hotkeyManager?.pause()
                } else {
                    self?.hotkeyManager?.resume()
                }
            }
            recorder.onConflict = { conflict in
                let alert = NSAlert()
                alert.messageText = "Shortcut Conflict"
                alert.informativeText = "Already used by \"\(conflict.titleEN)\" / \"\(conflict.titleTR)\"."
                alert.alertStyle = .warning
                alert.runModal()
            }
            recorder.onRecorded = { [weak self] modifiers, keyCode in
                // modifiers==0 clears the binding. keyCode 0 is valid (kVK_ANSI_A).
                if modifiers == 0 {
                    UserPreferences.shared.disableHotkey(for: action)
                } else {
                    UserPreferences.shared.setCustomHotkey(for: action, modifiers: modifiers, keyCode: keyCode)
                }
                self?.onHotkeysChanged()
            }
            contentView.addSubview(recorder)

            let reset = NSButton(title: "Reset", target: self, action: #selector(resetShortcut(_:)))
            reset.bezelStyle = .inline
            reset.frame = NSRect(x: 390, y: rowY, width: 70, height: 26)
            reset.tag = index
            contentView.addSubview(reset)
        }

        scrollView.documentView = contentView
        if let doc = scrollView.documentView {
            doc.scroll(NSPoint(x: 0, y: doc.bounds.maxY))
        }
        return scrollView
    }

    @objc private func resetShortcut(_ sender: NSButton) {
        let index = sender.tag
        let action = SnapAction.allCases[index]
        UserPreferences.shared.resetHotkey(for: action)
        onHotkeysChanged()

        guard let scrollView = tabView.tabViewItem(at: 1).view as? NSScrollView,
              let contentView = scrollView.documentView else { return }
        let recorderID = NSUserInterfaceItemIdentifier("recorder-\(index)")
        for subview in contentView.subviews {
            if let recorder = subview as? KeyRecorderView, recorder.identifier == recorderID {
                let hotkey = action.defaultHotkey
                recorder.setShortcut(modifiers: hotkey.modifiers, keyCode: hotkey.keyCode)
                break
            }
        }
    }
}
