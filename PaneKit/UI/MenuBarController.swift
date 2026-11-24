import AppKit

/// Menu bar status item and menus for PaneKit.
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let windowManager: WindowManager
    private let pinModeController: PinModeController
    private let workspaceController: WorkspaceController
    private let stashController: StashController
    private let onShowLayouts: () -> Void
    private let onShowPreferences: () -> Void
    private let onDragSnapPreferencesChanged: () -> Void
    private let onQuit: () -> Void

    private var lastFrontAppName: String = ""
    private var lastFrontAppBundleID: String = ""

    init(
        windowManager: WindowManager,
        pinModeController: PinModeController,
        workspaceController: WorkspaceController,
        stashController: StashController,
        onShowLayouts: @escaping () -> Void,
        onShowPreferences: @escaping () -> Void,
        onDragSnapPreferencesChanged: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) {
        self.windowManager = windowManager
        self.pinModeController = pinModeController
        self.workspaceController = workspaceController
        self.stashController = stashController
        self.onShowLayouts = onShowLayouts
        self.onShowPreferences = onShowPreferences
        self.onDragSnapPreferencesChanged = onDragSnapPreferencesChanged
        self.onQuit = onQuit
        super.init()
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = menuBarImage()
            button.image?.isTemplate = true
            button.toolTip = "PaneKit"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return }
        lastFrontAppName = app.localizedName ?? "App"
        lastFrontAppBundleID = bundleID
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(menu)
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        let trusted = AccessibilityPermission.isTrusted
        let axItem = NSMenuItem(
            title: trusted ? "Accessibility: OK ✓" : "Accessibility: Gerekli / Required ⚠",
            action: #selector(openAccessibility(_:)),
            keyEquivalent: ""
        )
        axItem.target = self
        axItem.identifier = NSUserInterfaceItemIdentifier("axStatus")
        menu.addItem(axItem)

        let requestItem = NSMenuItem(
            title: "Erişilebilirlik Ayarlarını Aç / Open Accessibility Settings",
            action: #selector(requestPermission(_:)),
            keyEquivalent: ""
        )
        requestItem.target = self
        menu.addItem(requestItem)

        let path = AccessibilityPermission.runningAppPath
        let pathItem = NSMenuItem(
            title: "Yol (kopyala): \(path)",
            action: #selector(copyBinaryPath(_:)),
            keyEquivalent: ""
        )
        pathItem.target = self
        pathItem.toolTip = """
        Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik
        Yalnızca bu yolu açın / Enable ONLY this path:

        \(path)

        Executable: \(AccessibilityPermission.runningExecutablePath)
        Önerilen: \(AccessibilityPermission.recommendedAppPath)
        """
        pathItem.identifier = NSUserInterfaceItemIdentifier("axPath")
        menu.addItem(pathItem)

        if AccessibilityPermission.isNonRecommendedPath {
            let warn = NSMenuItem(
                title: "⚠ Sadece ~/Applications/PaneKit.app kullanın",
                action: nil,
                keyEquivalent: ""
            )
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let layoutsItem = NSMenuItem(
            title: "Layouts…  (⌃⌥L)",
            action: #selector(showLayouts(_:)),
            keyEquivalent: "l"
        )
        layoutsItem.keyEquivalentModifierMask = [.control, .option]
        layoutsItem.target = self
        menu.addItem(layoutsItem)

        menu.addItem(makeWorkspacesMenuItem())

        let stashToggle = NSMenuItem(
            title: "Stash / Unstash  (⌃⌥`)",
            action: #selector(stashToggle(_:)),
            keyEquivalent: ""
        )
        stashToggle.target = self
        menu.addItem(stashToggle)

        let unstashAll = NSMenuItem(
            title: "Unstash All  (⌃⌥⇧`)",
            action: #selector(unstashAll(_:)),
            keyEquivalent: ""
        )
        unstashAll.target = self
        menu.addItem(unstashAll)

        let prefsItem = NSMenuItem(
            title: "Settings… / Ayarlar…",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let launchItem = NSMenuItem(
            title: "Açılışta başlat / Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = UserPreferences.shared.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let dragHeader = NSMenuItem(title: "Drag-to-Snap", action: nil, keyEquivalent: "")
        dragHeader.isEnabled = false
        menu.addItem(dragHeader)

        let dragToggle = NSMenuItem(
            title: "Kenara sürükle / Drag to edge",
            action: #selector(toggleDragSnap(_:)),
            keyEquivalent: ""
        )
        dragToggle.target = self
        dragToggle.state = UserPreferences.shared.dragSnapEnabled ? .on : .off
        menu.addItem(dragToggle)

        let splitToggle = NSMenuItem(
            title: "Kenar sürükle (böl / birleştir) / Drag shared edge",
            action: #selector(toggleSplitResize(_:)),
            keyEquivalent: ""
        )
        splitToggle.target = self
        splitToggle.state = UserPreferences.shared.splitResizeEnabled ? .on : .off
        menu.addItem(splitToggle)

        let greenToggle = NSMenuItem(
            title: "Yeşil düğme + ⌥ → Layouts",
            action: #selector(toggleOptionGreenLayouts(_:)),
            keyEquivalent: ""
        )
        greenToggle.target = self
        greenToggle.state = UserPreferences.shared.optionGreenButtonLayoutsEnabled ? .on : .off
        menu.addItem(greenToggle)

        let zoneMenu = NSMenu()
        for thickness in UserPreferences.snapZoneThicknessPresets {
            let label: String
            if thickness == UserPreferences.defaultSnapZoneThickness {
                label = "\(Int(thickness)) px (varsayılan / default)"
            } else {
                label = "\(Int(thickness)) px"
            }
            let item = NSMenuItem(
                title: label,
                action: #selector(selectSnapZoneThickness(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = thickness
            item.state = abs(UserPreferences.shared.snapZoneThickness - thickness) < 0.5 ? .on : .off
            zoneMenu.addItem(item)
        }
        let zoneItem = NSMenuItem(
            title: "Yapışma alanı / Snap zone…",
            action: nil,
            keyEquivalent: ""
        )
        zoneItem.submenu = zoneMenu
        menu.addItem(zoneItem)

        let insetMenu = NSMenu()
        for inset in UserPreferences.almostMaximizeInsetPresets {
            let label: String
            if inset == UserPreferences.defaultAlmostMaximizeInset {
                label = "\(Int(inset)) px (varsayılan / default)"
            } else {
                label = "\(Int(inset)) px"
            }
            let item = NSMenuItem(
                title: label,
                action: #selector(selectAlmostMaximizeInset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = inset
            item.state = abs(UserPreferences.shared.almostMaximizeInset - inset) < 0.5 ? .on : .off
            insetMenu.addItem(item)
        }
        let insetItem = NSMenuItem(
            title: "Neredeyse tam boşluk / Almost-max inset…",
            action: nil,
            keyEquivalent: ""
        )
        insetItem.submenu = insetMenu
        menu.addItem(insetItem)

        let gapMenu = NSMenu()
        for gap in UserPreferences.windowGapPresets {
            let label: String
            if gap == UserPreferences.defaultWindowGap {
                label = "\(Int(gap)) px (varsayılan / default)"
            } else {
                label = "\(Int(gap)) px"
            }
            let item = NSMenuItem(
                title: label,
                action: #selector(selectWindowGap(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = gap
            item.state = abs(UserPreferences.shared.windowGap - gap) < 0.5 ? .on : .off
            gapMenu.addItem(item)
        }
        let gapItem = NSMenuItem(
            title: "Pencere boşluğu / Window gap…",
            action: nil,
            keyEquivalent: ""
        )
        gapItem.submenu = gapMenu
        menu.addItem(gapItem)

        menu.addItem(.separator())

        let pinHeader = NSMenuItem(title: "Pin Mode", action: nil, keyEquivalent: "")
        pinHeader.isEnabled = false
        menu.addItem(pinHeader)

        if !lastFrontAppBundleID.isEmpty,
           !UserPreferences.shared.isAppIgnored(lastFrontAppBundleID) {
            let isCurrentPin = UserPreferences.shared.pinAppBundleID == lastFrontAppBundleID
            let pinAppTitle = isCurrentPin
                ? "Pin app: \"\(lastFrontAppName)\" ✓"
                : "Pin app olarak kullan / Use \"\(lastFrontAppName)\" as Pin App"
            let pinAppItem = NSMenuItem(
                title: pinAppTitle,
                action: #selector(setPinApp(_:)),
                keyEquivalent: ""
            )
            pinAppItem.target = self
            pinAppItem.representedObject = lastFrontAppBundleID
            pinAppItem.state = isCurrentPin ? .on : .off
            menu.addItem(pinAppItem)
        } else if let pinName = UserPreferences.shared.pinAppBundleID.map({ _ in UserPreferences.shared.pinAppName }) {
            let info = NSMenuItem(
                title: "Pin app: \(pinName)",
                action: nil,
                keyEquivalent: ""
            )
            info.isEnabled = false
            menu.addItem(info)
        }

        let pinToggle = NSMenuItem(
            title: "Pin Mode açık / Enable Pin Mode",
            action: #selector(togglePinMode(_:)),
            keyEquivalent: ""
        )
        pinToggle.target = self
        pinToggle.state = UserPreferences.shared.pinModeEnabled ? .on : .off
        pinToggle.isEnabled = UserPreferences.shared.pinAppBundleID != nil
        menu.addItem(pinToggle)

        let reflowItem = NSMenuItem(
            title: "Pin’i yeniden yerleştir / Reflow Pin",
            action: #selector(reflowPin(_:)),
            keyEquivalent: ""
        )
        reflowItem.target = self
        reflowItem.isEnabled = UserPreferences.shared.pinModeEnabled
        menu.addItem(reflowItem)

        menu.addItem(.separator())

        let snapHeader = NSMenuItem(title: "Snap", action: nil, keyEquivalent: "")
        snapHeader.isEnabled = false
        menu.addItem(snapHeader)

        for def in HotkeyDefinition.resolved() {
            let shortcut = def.isEnabled ? def.displayShortcut : "—"
            let item = NSMenuItem(
                title: "\(def.action.titleTR)  (\(shortcut))",
                action: #selector(snapFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = def.action.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if !lastFrontAppBundleID.isEmpty {
            let isIgnored = UserPreferences.shared.isAppIgnored(lastFrontAppBundleID)
            let ignoreTitle = isIgnored
                ? "Ignore kaldır / Stop Ignoring \"\(lastFrontAppName)\""
                : "Uygulamayı yok say / Ignore \"\(lastFrontAppName)\""
            let ignoreItem = NSMenuItem(
                title: ignoreTitle,
                action: #selector(toggleIgnoreApp(_:)),
                keyEquivalent: ""
            )
            ignoreItem.target = self
            ignoreItem.representedObject = lastFrontAppBundleID
            menu.addItem(ignoreItem)
            menu.addItem(.separator())
        }

        let about = NSMenuItem(
            title: "About PaneKit",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: "Quit PaneKit",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Workspaces menu

    private func makeWorkspacesMenuItem() -> NSMenuItem {
        let submenu = NSMenu()

        let saveItem = NSMenuItem(
            title: "Mevcut düzeni kaydet… / Save Current Workspace…",
            action: #selector(saveWorkspace(_:)),
            keyEquivalent: ""
        )
        saveItem.target = self
        submenu.addItem(saveItem)

        let restoreLast = NSMenuItem(
            title: "Son workspace’i yükle / Restore Last  (⌃⌥P)",
            action: #selector(restoreLastWorkspace(_:)),
            keyEquivalent: ""
        )
        restoreLast.target = self
        restoreLast.isEnabled = !UserPreferences.shared.workspaces.isEmpty
        submenu.addItem(restoreLast)

        submenu.addItem(.separator())

        let workspaces = UserPreferences.shared.workspaces
        if workspaces.isEmpty {
            let empty = NSMenuItem(title: "(Henüz yok / None saved)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for workspace in workspaces {
                let restore = NSMenuItem(
                    title: "Yükle / Restore “\(workspace.name)”",
                    action: #selector(restoreWorkspace(_:)),
                    keyEquivalent: ""
                )
                restore.target = self
                restore.representedObject = workspace.id
                submenu.addItem(restore)
            }

            submenu.addItem(.separator())

            let connectHeader = NSMenuItem(
                title: "Ekran bağlanınca yükle / On display connect",
                action: nil,
                keyEquivalent: ""
            )
            connectHeader.isEnabled = false
            submenu.addItem(connectHeader)

            let noneItem = NSMenuItem(
                title: "Kapalı / Off",
                action: #selector(selectDisplayConnectWorkspace(_:)),
                keyEquivalent: ""
            )
            noneItem.target = self
            noneItem.representedObject = ""
            noneItem.state = UserPreferences.shared.displayConnectWorkspaceID == nil ? .on : .off
            submenu.addItem(noneItem)

            for workspace in workspaces {
                let item = NSMenuItem(
                    title: workspace.name,
                    action: #selector(selectDisplayConnectWorkspace(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = workspace.id
                item.state = UserPreferences.shared.displayConnectWorkspaceID == workspace.id ? .on : .off
                submenu.addItem(item)
            }

            submenu.addItem(.separator())

            for workspace in workspaces {
                let delete = NSMenuItem(
                    title: "Sil / Delete “\(workspace.name)”",
                    action: #selector(deleteWorkspace(_:)),
                    keyEquivalent: ""
                )
                delete.target = self
                delete.representedObject = workspace.id
                submenu.addItem(delete)
            }
        }

        let item = NSMenuItem(title: "Workspaces…", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func showLayouts(_ sender: Any?) {
        onShowLayouts()
    }

    @objc private func stashToggle(_ sender: Any?) {
        stashController.toggleFocused()
    }

    @objc private func unstashAll(_ sender: Any?) {
        stashController.unstashAll()
    }

    @objc private func saveWorkspace(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Workspace kaydet / Save Workspace"
        alert.informativeText = "Açık pencerelerin konumları kaydedilir. / Saves positions of open windows."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        field.stringValue = "Workspace \(formatter.string(from: Date()))"
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        if workspaceController.saveCurrentWorkspace(named: name) == nil {
            let fail = NSAlert()
            fail.messageText = "Kaydedilemedi / Could Not Save"
            fail.informativeText = "Açık uygun pencere bulunamadı veya Accessibility kapalı."
            fail.alertStyle = .warning
            fail.runModal()
        }
    }

    @objc private func restoreLastWorkspace(_ sender: Any?) {
        let count = workspaceController.restoreLastWorkspace()
        if count == 0 {
            NSSound.beep()
        }
    }

    @objc private func restoreWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let count = workspaceController.restoreWorkspace(id: id)
        if count == 0 {
            NSSound.beep()
        }
    }

    @objc private func deleteWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        workspaceController.deleteWorkspace(id: id)
    }

    @objc private func selectDisplayConnectWorkspace(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? ""
        if raw.isEmpty {
            workspaceController.setDisplayConnectWorkspace(id: nil)
        } else {
            workspaceController.setDisplayConnectWorkspace(id: raw)
            UserPreferences.shared.restoreWorkspaceOnDisplayConnect = true
        }
    }

    @objc private func showPreferences(_ sender: Any?) {
        onShowPreferences()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        do {
            let status = try UserPreferences.shared.setLaunchAtLogin(enabled)
            sender.state = UserPreferences.shared.isLaunchAtLoginEnabled ? .on : .off
            if enabled, status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "Login Item Approval Required"
                alert.informativeText = "Allow PaneKit in System Settings → General → Login Items."
                alert.alertStyle = .informational
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } catch {
            sender.state = UserPreferences.shared.isLaunchAtLoginEnabled ? .on : .off
            let alert = NSAlert(error: error)
            alert.messageText = "Could Not Update Login Item"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func toggleDragSnap(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        UserPreferences.shared.dragSnapEnabled = enabled
        sender.state = enabled ? .on : .off
        onDragSnapPreferencesChanged()
    }

    @objc private func toggleSplitResize(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        UserPreferences.shared.splitResizeEnabled = enabled
        sender.state = enabled ? .on : .off
        onDragSnapPreferencesChanged()
    }

    @objc private func toggleOptionGreenLayouts(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        UserPreferences.shared.optionGreenButtonLayoutsEnabled = enabled
        sender.state = enabled ? .on : .off
        onDragSnapPreferencesChanged()
    }

    @objc private func selectSnapZoneThickness(_ sender: NSMenuItem) {
        guard let thickness = sender.representedObject as? CGFloat else { return }
        UserPreferences.shared.snapZoneThickness = thickness
        if let submenu = sender.menu {
            for item in submenu.items {
                guard let value = item.representedObject as? CGFloat else { continue }
                item.state = abs(value - thickness) < 0.5 ? .on : .off
            }
        }
        onDragSnapPreferencesChanged()
    }

    @objc private func selectAlmostMaximizeInset(_ sender: NSMenuItem) {
        guard let inset = sender.representedObject as? CGFloat else { return }
        UserPreferences.shared.almostMaximizeInset = inset
        if let submenu = sender.menu {
            for item in submenu.items {
                guard let value = item.representedObject as? CGFloat else { continue }
                item.state = abs(value - inset) < 0.5 ? .on : .off
            }
        }
    }

    @objc private func selectWindowGap(_ sender: NSMenuItem) {
        guard let gap = sender.representedObject as? CGFloat else { return }
        UserPreferences.shared.windowGap = gap
        if let submenu = sender.menu {
            for item in submenu.items {
                guard let value = item.representedObject as? CGFloat else { continue }
                item.state = abs(value - gap) < 0.5 ? .on : .off
            }
        }
        if UserPreferences.shared.pinModeEnabled {
            pinModeController.reflow()
        }
    }

    @objc private func setPinApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        let name = lastFrontAppBundleID == bundleID ? lastFrontAppName : UserPreferences.shared.pinAppName
        pinModeController.setPinApp(bundleID: bundleID, name: name.isEmpty ? "App" : name)
    }

    @objc private func togglePinMode(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        let ok = pinModeController.setPinModeEnabled(enable)
        sender.state = (ok && UserPreferences.shared.pinModeEnabled) ? .on : .off
        if enable, !ok {
            let alert = NSAlert()
            alert.messageText = "Pin App Required"
            alert.informativeText = "Önce bir uygulamayı Pin App olarak seçin / Choose a Pin App first."
            alert.alertStyle = .informational
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func reflowPin(_ sender: Any?) {
        pinModeController.reflow()
    }

    @objc private func snapFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = SnapAction(rawValue: raw) else { return }
        windowManager.snap(action)
    }

    @objc private func toggleIgnoreApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if UserPreferences.shared.isAppIgnored(bundleID) {
            UserPreferences.shared.removeIgnoredApp(bundleID)
        } else {
            UserPreferences.shared.addIgnoredApp(bundleID)
        }
    }

    @objc private func openAccessibility(_ sender: Any?) {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func requestPermission(_ sender: Any?) {
        // Open Settings only — never Apple's AX modal (rebuilds would re-prompt).
        AccessibilityPermission.requestExplicitly()
    }

    @objc private func copyBinaryPath(_ sender: Any?) {
        let path = AccessibilityPermission.runningAppPath
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc private func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let alert = NSAlert()
        alert.messageText = "PaneKit"
        alert.informativeText = """
        Version \(version)

        Ücretsiz macOS pencere yöneticisi / Free macOS window manager.

        • Layouts… (⌃⌥L): Windows tarzı çoklu pencere yerleşimi
        • Kenara sürükle: dar magnet alanı (varsayılan 6 px)
        • Ekranlar arası taşıma, Restore, özelleştirilebilir kısayollar
        • Settings… menüsünden Launch at Login ve kısayollar

        See README.md for the full shortcut list.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit()
    }

    // MARK: - Icon

    private func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2)
            NSColor.black.setStroke()
            path.lineWidth = 1.5
            path.stroke()

            let midX = inset.midX
            let midY = inset.midY
            let v = NSBezierPath()
            v.move(to: NSPoint(x: midX, y: inset.minY))
            v.line(to: NSPoint(x: midX, y: inset.maxY))
            v.lineWidth = 1
            v.stroke()

            let h = NSBezierPath()
            h.move(to: NSPoint(x: inset.minX, y: midY))
            h.line(to: NSPoint(x: inset.maxX, y: midY))
            h.lineWidth = 1
            h.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
