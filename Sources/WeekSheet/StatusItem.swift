import AppKit
import ServiceManagement

public final class StatusItem {
    private let statusItem: NSStatusItem
    private let windowController: WindowController
    private var launchAtLogin: Bool

    public init(windowController: WindowController) {
        self.windowController = windowController
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "calendar.day.timeline.leading",
                accessibilityDescription: "Week Sheet"
            )
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let editItem = NSMenuItem(
            title: "Toggle Edit Mode",
            action: #selector(WindowController.toggleEditMode),
            keyEquivalent: ""
        )
        editItem.target = windowController
        editItem.keyEquivalentModifierMask = [.control, .option]
        editItem.keyEquivalent = " "
        menu.addItem(editItem)

        let visibilityItem = NSMenuItem(
            title: windowController.isSheetHidden ? "Show Sheet" : "Hide Sheet",
            action: #selector(toggleVisibilityFromMenu),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        visibilityItem.keyEquivalentModifierMask = [.control, .option]
        visibilityItem.keyEquivalent = "m"
        menu.addItem(visibilityItem)

        let layoutItem = NSMenuItem(
            title: UserDefaults.standard.bool(forKey: "horizontalMode") ? "Vertical Layout" : "Horizontal Layout",
            action: #selector(toggleLayoutFromMenu),
            keyEquivalent: ""
        )
        layoutItem.target = self
        layoutItem.keyEquivalentModifierMask = [.control, .option]
        layoutItem.keyEquivalent = "."
        menu.addItem(layoutItem)

        // A setting rather than an action: checked, the window keeps today in the second column;
        // unchecked, it starts on Monday. Either way navigation moves one column at a time, so
        // this only decides where the window sits when it snaps back to today.
        let followTodayItem = NSMenuItem(
            title: "Follow Today",
            action: #selector(toggleWindowModeFromMenu),
            keyEquivalent: ""
        )
        followTodayItem.target = self
        followTodayItem.state = UserDefaults.standard.bool(forKey: "slidingMode") ? .on : .off
        menu.addItem(followTodayItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Week Sheet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleVisibilityFromMenu() {
        windowController.toggleVisibility()
        statusItem.menu = buildMenu()
    }

    @objc private func toggleLayoutFromMenu() {
        windowController.toggleLayoutMode()
        statusItem.menu = buildMenu()
    }

    @objc private func toggleWindowModeFromMenu() {
        windowController.toggleWindowMode()
        statusItem.menu = buildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()
            statusItem.menu = buildMenu()
        } catch {
            // SMAppService may fail outside a proper app bundle — silently ignore
        }
    }
}
