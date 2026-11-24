import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()
    private var hotkeyManager: HotkeyManager?
    private var menuBarController: MenuBarController?
    private var layoutController: LayoutController?
    private var dragSnapManager: DragSnapManager?
    private var splitResizeManager: SplitResizeManager?
    private var greenButtonLayoutsTrigger: GreenButtonLayoutsTrigger?
    private var pinModeController: PinModeController?
    private var workspaceController: WorkspaceController?
    private var stashController: StashController?
    private var preferencesWindow: PreferencesWindowController?
    private var accessibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: hide from Dock (also set via LSUIElement).
        NSApp.setActivationPolicy(.accessory)

        let layouts = LayoutController(windowManager: windowManager)
        layoutController = layouts

        let dragSnap = DragSnapManager(windowManager: windowManager)
        dragSnapManager = dragSnap

        let splitResize = SplitResizeManager(windowManager: windowManager)
        splitResizeManager = splitResize

        let greenButton = GreenButtonLayoutsTrigger(
            windowManager: windowManager,
            onShowLayouts: { [weak layouts] in
                layouts?.showLayouts()
            },
            isLayoutsVisible: { [weak layouts] in
                layouts?.isShowingLayouts ?? false
            }
        )
        greenButtonLayoutsTrigger = greenButton

        let pin = PinModeController(windowManager: windowManager)
        pinModeController = pin
        windowManager.pinModeReflow = { [weak pin] in
            pin?.reflow()
        }

        let workspaces = WorkspaceController(windowManager: windowManager)
        workspaceController = workspaces
        windowManager.restoreLastWorkspaceHandler = { [weak workspaces] in
            let count = workspaces?.restoreLastWorkspace() ?? 0
            if count == 0 {
                NSSound.beep()
            }
        }
        workspaces.start()

        let stash = StashController(windowManager: windowManager)
        stashController = stash
        windowManager.stashToggleHandler = { [weak stash] in
            stash?.toggleFocused()
        }
        windowManager.unstashAllHandler = { [weak stash] in
            stash?.unstashAll()
        }
        windowManager.isWindowStashed = { [weak stash] id in
            stash?.isStashed(id: id) ?? false
        }
        stash.start()

        let hotkeys = HotkeyManager(
            onAction: { [weak self] action in
                self?.windowManager.snap(action)
            },
            onShowLayouts: { [weak layouts] in
                layouts?.showLayouts()
            }
        )
        hotkeys.register()
        hotkeyManager = hotkeys

        let menu = MenuBarController(
            windowManager: windowManager,
            pinModeController: pin,
            workspaceController: workspaces,
            stashController: stash,
            onShowLayouts: { [weak layouts] in
                layouts?.showLayouts()
            },
            onShowPreferences: { [weak self] in
                self?.showPreferences()
            },
            onDragSnapPreferencesChanged: { [weak dragSnap, weak splitResize, weak greenButton, weak stash] in
                dragSnap?.reload()
                splitResize?.reload()
                greenButton?.reload()
                stash?.reload()
            },
            onQuit: { [weak self] in
                self?.layoutController?.dismissAll()
                self?.dragSnapManager?.stop()
                self?.splitResizeManager?.stop()
                self?.greenButtonLayoutsTrigger?.stop()
                self?.workspaceController?.stop()
                self?.stashController?.stop()
                self?.hotkeyManager?.unregister()
                NSApp.terminate(nil)
            }
        )
        menu.setup()
        menuBarController = menu

        // Opens System Settings once per binary if untrusted — never Apple's AX modal.
        AccessibilityPermission.requestIfNeeded()

        // Start after the trust check so the tap can attach when trusted.
        dragSnap.start()
        splitResize.start()
        greenButton.start()

        if pin.isEnabled {
            pin.reflow()
        }

        // Refresh AX status when returning from System Settings; start drag-snap if now trusted.
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // start() is a no-op if the tap already exists or feature is disabled.
            self?.dragSnapManager?.start()
            self?.splitResizeManager?.start()
            self?.greenButtonLayoutsTrigger?.start()
        }
    }

    private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(
                hotkeyManager: hotkeyManager,
                onHotkeysChanged: { [weak self] in
                    self?.hotkeyManager?.reload()
                },
                onDragSnapChanged: { [weak self] in
                    self?.dragSnapManager?.reload()
                    self?.splitResizeManager?.reload()
                    self?.greenButtonLayoutsTrigger?.reload()
                    self?.stashController?.reload()
                },
                onPinPreferencesChanged: { [weak self] in
                    if UserPreferences.shared.pinModeEnabled {
                        self?.pinModeController?.reflow()
                    }
                }
            )
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        layoutController?.dismissAll()
        dragSnapManager?.stop()
        splitResizeManager?.stop()
        greenButtonLayoutsTrigger?.stop()
        workspaceController?.stop()
        stashController?.stop()
        hotkeyManager?.unregister()
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
