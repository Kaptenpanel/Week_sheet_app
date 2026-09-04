import AppKit
import Combine
import SwiftUI
import Carbon

private class SheetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

public final class WindowController: NSObject {
    private let window: NSWindow
    private let viewModel: SheetViewModel
    private var hotKeyRef: EventHotKeyRef?
    private var globalClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    public init(store: FileStore) {
        self.viewModel = SheetViewModel(store: store)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = screen.frame.width * 0.6
        let height = width * (9.0 / 16.0)
        let x = (screen.frame.width - width) / 2
        let y = (screen.frame.height - height) / 2
        let frame = NSRect(x: x, y: y, width: width, height: height)

        let window = SheetWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrameAutosaveName("WeekSheet")
        self.window = window

        super.init()

        window.contentView = NSHostingView(rootView: SheetView(viewModel: viewModel))

        applyBackgroundMode()
        window.orderFront(nil)
        registerHotKey()

        viewModel.$isEditMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] editing in
                guard let self else { return }
                if editing { self.enterEditMode() } else { self.leaveEditMode() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, !self.viewModel.isEditMode else { return }
            let point = event.locationInWindow
            guard self.window.frame.contains(point) else { return }
            if self.isDesktopVisibleAt(point) {
                DispatchQueue.main.async { self.viewModel.isEditMode = true }
            }
        }
    }

    private func isDesktopVisibleAt(_ screenPoint: NSPoint) -> Bool {
        let flippedY = NSScreen.main.map { $0.frame.height - screenPoint.y } ?? screenPoint.y
        let cgPoint = CGPoint(x: screenPoint.x, y: flippedY)
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        let myNumber = window.windowNumber
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0 else { continue }
            guard let wid = info[kCGWindowNumber as String] as? Int, wid != myNumber else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(cgPoint) { return false }
        }
        return true
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Edit mode

    @objc public func toggleEditMode() {
        viewModel.isEditMode.toggle()
    }

    private func enterEditMode() {
        viewModel.installKeyHandler()
        window.level = .floating
        window.ignoresMouseEvents = false
        window.alphaValue = 1.0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func leaveEditMode() {
        viewModel.removeKeyHandler()
        viewModel.cancelEditing()
        applyBackgroundMode()
    }

    private func applyBackgroundMode() {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.ignoresMouseEvents = true
        window.alphaValue = 0.85
        window.orderBack(nil)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        if viewModel.isEditMode { viewModel.isEditMode = false }
    }

    // MARK: - Hotkey (⌃⌥Space)

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("WSHT"), id: 1)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            selfPtr,
            nil
        )

        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<WindowController>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { controller.toggleEditMode() }
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | OSType(char)
    }
    return result
}
