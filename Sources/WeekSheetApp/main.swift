import AppKit
import WeekSheet

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: WindowController!
    private var statusItem: StatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = FileStore()
        _ = try? store.loadAndResetIfNeeded()
        windowController = WindowController(store: store)
        statusItem = StatusItem(windowController: windowController)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
