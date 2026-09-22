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
    private var editHotKeyRef: EventHotKeyRef?
    private var visibilityHotKeyRef: EventHotKeyRef?
    private var layoutHotKeyRef: EventHotKeyRef?
    private var backHotKeyRef: EventHotKeyRef?
    private var forwardHotKeyRef: EventHotKeyRef?
    private var todayHotKeyRef: EventHotKeyRef?
    private var globalClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private(set) var isSheetHidden = false

    public init(store: FileStore) {
        self.viewModel = SheetViewModel(store: store)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = screen.frame.width * 0.6
        let isHorizontal = UserDefaults.standard.bool(forKey: "horizontalMode")
        let height = isHorizontal ? width * (4.0 / 5.0) : width * (9.0 / 16.0)
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
        if let ref = editHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = visibilityHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = layoutHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = backHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = forwardHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = todayHotKeyRef { UnregisterEventHotKey(ref) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Edit mode

    @objc public func toggleEditMode() {
        guard !isSheetHidden else { return }
        viewModel.isEditMode.toggle()
    }

    @objc public func toggleVisibility() {
        if isSheetHidden {
            isSheetHidden = false
            if viewModel.isEditMode {
                enterEditMode()
            } else {
                applyBackgroundMode()
                window.orderFront(nil)
            }
        } else {
            // Edit mode survives hiding; only the key handler is paused.
            // Set the flag first so windowDidResignKey ignores the orderOut.
            isSheetHidden = true
            viewModel.removeKeyHandler()
            window.orderOut(nil)
        }
    }

    @objc public func toggleLayoutMode() {
        viewModel.toggleLayoutMode()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = window.frame.width
        let height: CGFloat
        if viewModel.isHorizontalMode {
            height = width * (4.0 / 5.0)
        } else {
            height = width * (9.0 / 16.0)
        }
        let y = window.frame.midY - height / 2
        let newFrame = NSRect(x: window.frame.origin.x, y: max(y, screen.visibleFrame.minY), width: width, height: height)
        window.setFrame(newFrame, display: true, animate: true)
    }

    @objc public func stepBack() { viewModel.stepBack() }
    @objc public func stepForward() { viewModel.stepForward() }
    @objc public func goToToday() { viewModel.goToToday() }
    @objc public func toggleWindowMode() { viewModel.toggleWindowMode() }

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
        guard !isSheetHidden else { return }
        if viewModel.isEditMode { viewModel.isEditMode = false }
    }

    // MARK: - Hotkeys

    private func registerHotKey() {
        let sig = fourCharCode("WSHT")
        let modifiers = UInt32(controlKey | optionKey)
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
            UInt32(kVK_Space), modifiers,
            EventHotKeyID(signature: sig, id: 1),
            GetApplicationEventTarget(), 0,
            &editHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_M), modifiers,
            EventHotKeyID(signature: sig, id: 2),
            GetApplicationEventTarget(), 0,
            &visibilityHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_Period), modifiers,
            EventHotKeyID(signature: sig, id: 3),
            GetApplicationEventTarget(), 0,
            &layoutHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_LeftArrow), modifiers,
            EventHotKeyID(signature: sig, id: 4),
            GetApplicationEventTarget(), 0,
            &backHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_RightArrow), modifiers,
            EventHotKeyID(signature: sig, id: 5),
            GetApplicationEventTarget(), 0,
            &forwardHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_0), modifiers,
            EventHotKeyID(signature: sig, id: 6),
            GetApplicationEventTarget(), 0,
            &todayHotKeyRef
        )
        // Follow Today has no hotkey: it is a setting you pick once, not an action you repeat, so
        // it lives only in the menu bar.
    }
}

private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let controller = Unmanaged<WindowController>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        switch hotKeyID.id {
        case 1: controller.toggleEditMode()
        case 2: controller.toggleVisibility()
        case 3: controller.toggleLayoutMode()
        case 4: controller.stepBack()
        case 5: controller.stepForward()
        case 6: controller.goToToday()
        default: break
        }
    }
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | OSType(char)
    }
    return result
}
