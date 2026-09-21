import AppKit
import SwiftUI

// MARK: - Palette

private let paperColor = Color(nsColor: NSColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1))
private let ruleColor = Color.black.opacity(0.10)
private let marginLine = Color.black.opacity(0.04)
private let todayGreen = Color(nsColor: NSColor(red: 0.29, green: 0.50, blue: 0.31, alpha: 1))
private let todayTint = Color(nsColor: NSColor(red: 0.29, green: 0.50, blue: 0.31, alpha: 0.06))
private let todayBar = Color(nsColor: NSColor(red: 0.29, green: 0.50, blue: 0.31, alpha: 0.85))
private let warmPanel = Color(nsColor: NSColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1))
private let greenPanel = Color(nsColor: NSColor(red: 0.91, green: 0.95, blue: 0.91, alpha: 1))
private let coolPanel = Color(nsColor: NSColor(red: 0.91, green: 0.93, blue: 0.97, alpha: 1))
private let chipBorder = Color.black.opacity(0.20)
private let chipText = Color.black.opacity(0.50)
private let labelDim = Color.black.opacity(0.40)
private let footerDim = Color.black.opacity(0.35)
private let bodyText = Color.black.opacity(0.85)
private let selectionBg = Color.black.opacity(0.06)

private let titleFont = Font.system(size: 14, weight: .bold, design: .monospaced)
private let headerFont = Font.system(size: 11, weight: .semibold, design: .monospaced)
private let smallMono = Font.system(size: 10, weight: .regular, design: .monospaced)
private let captionMono = Font.system(size: 9, weight: .medium, design: .monospaced)
private let bodyFont = Font.system(size: 12, weight: .regular, design: .default)
private let italicBody = Font.system(size: 11, weight: .regular, design: .default).italic()

// MARK: - SheetViewModel

public final class SheetViewModel: ObservableObject {
    @Published var sheet: Sheet
    @Published var isEditMode = false
    @Published var selectedID: UUID?
    @Published var editingID: UUID?
    @Published var addingBucket: BucketKey?
    @Published var addingIdea = false
    @Published var editingReminder = false
    @Published private(set) var undoState: UndoInfo?
    @Published var shakingBucket: BucketKey?
    @Published var isHorizontalMode: Bool
    /// Which six buckets to render. Week mode until Task 8 adds the toggle.
    @Published var windowMode: WindowMode = .week
    /// The date the window is built around. View state — never persisted, so a relaunch
    /// always opens on today.
    @Published var anchor = Date()
    /// Start of the current day. Published so the sheet redraws when the date rolls over.
    @Published private(set) var today = Calendar.current.startOfDay(for: Date())

    let store: FileStore
    private var eventMonitor: Any?
    private var undoTimer: Timer?
    private var tickTimer: Timer?
    private var wakeObserver: Any?

    struct UndoInfo { let item: Item; let bucket: BucketKey?; let position: Int }

    var window: [BucketKey] { Sheet.window(anchor: anchor, mode: windowMode) }

    public init(store: FileStore) {
        self.store = store
        self.isHorizontalMode = UserDefaults.standard.bool(forKey: "horizontalMode")
        self.sheet = (try? store.loadAndPrune()) ?? .empty()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so the tick still fires while a menu or window drag runs a tracking loop.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        // Timers are coalesced across sleep; catch up as soon as the machine wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tick()
        }
    }

    deinit {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        undoTimer?.invalidate()
        tickTimer?.invalidate()
    }

    private func save() { try? store.save(sheet) }

    /// Rolls the highlighted day forward at midnight, moves the window with the calendar, and
    /// drops buckets past the horizon.
    func tick(now: Date = Date()) {
        let start = Calendar.current.startOfDay(for: now)
        if start != today {
            today = start
            // The window is a pure function of the anchor, so the anchor has to follow the
            // calendar -- otherwise the sheet keeps showing the week that has just ended, with
            // no column highlighted once the new day falls outside it.
            anchor = now
        }
        pruneIfNeeded(now: now)
    }

    func pruneIfNeeded(now: Date = Date()) {
        let countBefore = sheet.buckets.count
        sheet.prune(now: now)
        if sheet.buckets.count != countBefore { save() }
    }

    func addItem(to key: BucketKey, text: String) {
        addingBucket = nil
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        _ = try? sheet.addItem(to: key, text: t)
        save()
    }

    func addIdea(text: String) {
        addingIdea = false
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        sheet.addIdea(text: t)
        save()
    }

    func toggleDone() {
        guard let id = selectedID else { return }
        if sheet.ideas.contains(where: { $0.id == id }) { return }
        try? sheet.toggleDone(id)
        save()
    }

    func deleteItem(_ id: UUID) {
        var foundItem: Item?
        var foundBucket: BucketKey?
        var foundPos = 0
        for key in Array(sheet.buckets.keys) {
            if let idx = sheet.buckets[key]?.firstIndex(where: { $0.id == id }) {
                foundItem = sheet.buckets[key]![idx]; foundBucket = key; foundPos = idx; break
            }
        }
        if foundItem == nil, let idx = sheet.ideas.firstIndex(where: { $0.id == id }) {
            foundItem = sheet.ideas[idx]; foundPos = idx
        }
        guard let item = foundItem else { return }
        try? sheet.deleteItem(id)
        if selectedID == id { selectedID = nil }
        save()
        undoTimer?.invalidate()
        undoState = UndoInfo(item: item, bucket: foundBucket, position: foundPos)
        undoTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.undoState = nil }
        }
    }

    func undo() {
        guard let info = undoState else { return }
        undoTimer?.invalidate()
        undoState = nil
        if let bucket = info.bucket {
            let items = sheet.buckets[bucket, default: []]
            if items.count < Sheet.maxItemsPerDay {
                sheet.buckets[bucket, default: []].insert(info.item, at: min(info.position, items.count))
            } else {
                sheet.ideas.append(info.item)
            }
        } else {
            sheet.ideas.insert(info.item, at: min(info.position, sheet.ideas.count))
        }
        save()
    }

    func updateText(_ id: UUID, newText: String) {
        editingID = nil
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        for key in Array(sheet.buckets.keys) {
            if let idx = sheet.buckets[key]?.firstIndex(where: { $0.id == id }) {
                sheet.buckets[key]![idx].text = t; save(); return
            }
        }
        if let idx = sheet.ideas.firstIndex(where: { $0.id == id }) {
            sheet.ideas[idx].text = t; save()
        }
    }

    func select(_ id: UUID?) {
        if editingID != nil { editingID = nil }
        selectedID = id
        if addingBucket != nil { addingBucket = nil }
        if addingIdea { addingIdea = false }
    }

    func startAddingToBucket(_ key: BucketKey) {
        guard sheet.buckets[key, default: []].count < Sheet.maxItemsPerDay else { return }
        addingBucket = key; editingID = nil; selectedID = nil
    }

    func startAddingIdea() { addingIdea = true; editingID = nil; selectedID = nil }

    func startEditing(_ id: UUID) { editingID = id; selectedID = id }

    func startEditingReminder() { editingReminder = true; editingID = nil; selectedID = nil; addingBucket = nil; addingIdea = false }

    func updateReminder(_ text: String) {
        editingReminder = false
        sheet.setFocus(text.trimmingCharacters(in: .whitespaces), for: anchor)
        save()
    }

    func moveItemToBucket(_ id: UUID, bucket: BucketKey, position: Int) {
        do {
            try sheet.moveItem(id, to: bucket, at: position)
            save()
        } catch SheetError.dayFull {
            shakingBucket = bucket
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if self?.shakingBucket == bucket { self?.shakingBucket = nil }
            }
        } catch {}
    }

    func moveItemToIdeas(_ id: UUID) {
        try? sheet.moveToIdeas(id)
        save()
    }

    func cancelEditing() { editingID = nil; addingBucket = nil; addingIdea = false; editingReminder = false; selectedID = nil }

    func toggleLayoutMode() {
        isHorizontalMode.toggle()
        UserDefaults.standard.set(isHorizontalMode, forKey: "horizontalMode")
    }

    // MARK: Key handler

    func installKeyHandler() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.editingID != nil || self.addingBucket != nil || self.addingIdea { return event }
            // Reminder gets typed keys (incl. Space); Esc still leaves edit mode.
            if self.editingReminder && event.keyCode != 53 { return event }
            switch event.keyCode {
            case 49: self.toggleDone(); return nil
            case 51: if let id = self.selectedID { self.deleteItem(id); return nil }; return event
            case 53: self.isEditMode = false; return nil
            default: return event
            }
        }
    }

    func removeKeyHandler() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }
}

// MARK: - InlineTextField

private struct InlineTextField: NSViewRepresentable {
    let text: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.stringValue = text
        f.font = .systemFont(ofSize: 12)
        f.isBordered = false
        f.drawsBackground = false
        f.textColor = .black
        f.focusRingType = .none
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.delegate = context.coordinator
        DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit, onCancel: onCancel) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let onCommit: (String) -> Void
        let onCancel: () -> Void
        private var handled = false

        init(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onCommit = onCommit; self.onCancel = onCancel
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                handled = true
                let t = control.stringValue.trimmingCharacters(in: .whitespaces)
                t.isEmpty ? onCancel() : onCommit(t)
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                handled = true; onCancel(); return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !handled else { return }
            handled = true
            let t = (obj.object as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
            t.isEmpty ? onCancel() : onCommit(t)
        }
    }
}

// MARK: - SheetView

public struct SheetView: View {
    @ObservedObject var viewModel: SheetViewModel

    public init(viewModel: SheetViewModel) { self.viewModel = viewModel }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            paperColor.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.select(nil) }
            Rectangle().fill(marginLine).frame(width: 1).padding(.leading, 22)
                .allowsHitTesting(false)

            if viewModel.isHorizontalMode {
                VStack(spacing: 0) {
                    header.padding(.bottom, 16)
                    HStack(alignment: .top, spacing: 16) {
                        dayRows
                        sidebar.frame(width: 280)
                    }
                    .padding(.bottom, 12)
                    horizontalFooter
                }
                .padding(24)
            } else {
                VStack(spacing: 0) {
                    header.padding(.bottom, 16)
                    dayColumns.padding(.bottom, 16)
                    bottom.padding(.bottom, 12)
                    footer
                }
                .padding(24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottom) {
            if viewModel.undoState != nil {
                UndoToast(onUndo: viewModel.undo).padding(.bottom, 40)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("WEEK SHEET").font(titleFont).foregroundColor(.black.opacity(0.8))
            Text(dateRangeText).font(smallMono).foregroundColor(labelDim)
            Spacer()
            if viewModel.isEditMode {
                Text("EDIT MODE").font(smallMono).foregroundColor(labelDim)
            }
        }
    }

    // MARK: Day columns

    private var dayColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(viewModel.window, id: \.self) { key in
                dayColumn(key).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ key: BucketKey) -> some View {
        let items = viewModel.sheet.buckets[key, default: []]
        let isToday = (key == BucketKey.containing(viewModel.today))
        let isShaking = viewModel.shakingBucket == key

        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(isToday ? todayBar : Color.clear).frame(height: 2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(key.headerLabel).font(headerFont)
                Text(key.compactDateLabel).font(smallMono)
            }
            .foregroundColor(isToday ? todayGreen : .black.opacity(0.65))
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(isShaking ? Color.red.opacity(0.12) : Color.clear)
            .cornerRadius(3)

            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 0) {
                    if i < items.count {
                        if viewModel.editingID == items[i].id {
                            InlineTextField(
                                text: items[i].text,
                                onCommit: { viewModel.updateText(items[i].id, newText: $0) },
                                onCancel: { viewModel.editingID = nil }
                            ).frame(height: 28)
                        } else {
                            itemSlot(items[i])
                        }
                    } else if viewModel.addingBucket == key && i == items.count {
                        InlineTextField(
                            text: "",
                            onCommit: { viewModel.addItem(to: key, text: $0) },
                            onCancel: { viewModel.addingBucket = nil }
                        ).frame(height: 28)
                    } else {
                        Rectangle().fill(Color.clear).frame(height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.startAddingToBucket(key) }
                    }
                    Rectangle().fill(ruleColor).frame(height: 1)
                }
                .padding(.horizontal, 8)
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleDrop(providers, to: key, at: i)
                }
            }
        }
        .background(isToday ? todayTint : Color.clear)
        .modifier(ShakeEffect(shaking: isShaking))
    }

    private func handleDrop(_ providers: [NSItemProvider], to key: BucketKey, at position: Int) -> Bool {
        guard viewModel.isEditMode else { return false }
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidString = string as? String, let id = UUID(uuidString: uuidString) else { return }
            DispatchQueue.main.async { self.viewModel.moveItemToBucket(id, bucket: key, position: position) }
        }
        return true
    }

    private func itemSlot(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\u{2022}").font(bodyFont)
            Text(item.text).font(bodyFont).strikethrough(item.done)
        }
        .foregroundColor(bodyText)
        .opacity(item.done ? 0.5 : 1.0)
        .frame(height: 28, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(viewModel.selectedID == item.id ? selectionBg : Color.clear)
        .cornerRadius(3)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onTapGesture(count: 2) { viewModel.startEditing(item.id) }
        .onTapGesture(count: 1) { viewModel.select(item.id) }
    }

    // MARK: Bottom

    private var bottom: some View {
        HStack(alignment: .top, spacing: 16) {
            ideasPanel
            reminderPanel
        }
    }

    private var ideasPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEW IDEAS").font(headerFont).foregroundColor(.black.opacity(0.6))
                Text("\(viewModel.sheet.ideas.count)").font(smallMono).foregroundColor(labelDim)
                Spacer()
                Text("+")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(labelDim)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(ruleColor, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.startAddingIdea() }
            }

            FlowLayout(spacing: 8) {
                ForEach(viewModel.sheet.ideas) { idea in
                    if viewModel.editingID == idea.id {
                        InlineTextField(
                            text: idea.text,
                            onCommit: { viewModel.updateText(idea.id, newText: $0) },
                            onCancel: { viewModel.editingID = nil }
                        )
                        .frame(width: 150, height: 22)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundColor(chipBorder))
                    } else {
                        chip(idea)
                    }
                }
            }

            if viewModel.addingIdea {
                InlineTextField(
                    text: "",
                    onCommit: { viewModel.addIdea(text: $0) },
                    onCancel: { viewModel.addingIdea = false }
                )
                .frame(height: 22)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(chipBorder))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(warmPanel)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(ruleColor, lineWidth: 1))
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard viewModel.isEditMode, let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { string, _ in
                guard let uuidString = string as? String, let id = UUID(uuidString: uuidString) else { return }
                DispatchQueue.main.async { self.viewModel.moveItemToIdeas(id) }
            }
            return true
        }
    }

    private func chip(_ idea: Item) -> some View {
        HStack(spacing: 4) {
            Text(idea.text).font(italicBody).foregroundColor(chipText)
            Text("\u{00D7}")
                .font(.system(size: 12))
                .foregroundColor(chipText.opacity(0.7))
                .contentShape(Rectangle())
                .onTapGesture { viewModel.deleteItem(idea.id) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(viewModel.selectedID == idea.id ? selectionBg : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundColor(chipBorder))
        .onDrag {
            NSItemProvider(object: idea.id.uuidString as NSString)
        }
        .onTapGesture(count: 2) { viewModel.startEditing(idea.id) }
        .onTapGesture(count: 1) { viewModel.select(idea.id) }
    }

    private var reminderPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REMINDER !").font(headerFont).foregroundColor(.black.opacity(0.6))
            ZStack(alignment: .leading) {
                Text(viewModel.sheet.focus(for: viewModel.anchor).isEmpty ? " " : viewModel.sheet.focus(for: viewModel.anchor))
                    .font(bodyFont).foregroundColor(bodyText)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    .opacity(viewModel.editingReminder ? 0 : 1)
                if viewModel.editingReminder && viewModel.isEditMode {
                    InlineTextField(
                        text: viewModel.sheet.focus(for: viewModel.anchor),
                        onCommit: { viewModel.updateReminder($0) },
                        onCancel: { viewModel.editingReminder = false }
                    ).frame(maxWidth: .infinity)
                }
            }
            .padding(6).background(Color.white.opacity(0.5)).cornerRadius(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(greenPanel).cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isEditMode && !viewModel.editingReminder { viewModel.startEditingReminder() }
        }
    }

    // MARK: Horizontal layout

    private var dayRows: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.window, id: \.self) { key in
                dayRow(key)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dayRow(_ key: BucketKey) -> some View {
        let items = viewModel.sheet.buckets[key, default: []]
        let isToday = (key == BucketKey.containing(viewModel.today))
        let isShaking = viewModel.shakingBucket == key

        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(isToday ? todayBar : Color.clear).frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(key.headerLabel).font(headerFont)
                Text(key.wideDateLabel).font(smallMono)
            }
            .foregroundColor(isToday ? todayGreen : .black.opacity(0.65))
            .frame(width: 70, alignment: .leading)
            .padding(.vertical, 8).padding(.leading, 8)
            .background(isShaking ? Color.red.opacity(0.12) : Color.clear)
            .cornerRadius(3)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 0) {
                        if i < items.count {
                            if viewModel.editingID == items[i].id {
                                InlineTextField(
                                    text: items[i].text,
                                    onCommit: { viewModel.updateText(items[i].id, newText: $0) },
                                    onCancel: { viewModel.editingID = nil }
                                ).frame(height: 28)
                            } else {
                                itemSlot(items[i])
                            }
                        } else if viewModel.addingBucket == key && i == items.count {
                            InlineTextField(
                                text: "",
                                onCommit: { viewModel.addItem(to: key, text: $0) },
                                onCancel: { viewModel.addingBucket = nil }
                            ).frame(height: 28)
                        } else {
                            Rectangle().fill(Color.clear).frame(height: 28)
                                .contentShape(Rectangle())
                                .onTapGesture { viewModel.startAddingToBucket(key) }
                        }
                        Rectangle().fill(ruleColor).frame(height: 1)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        handleDrop(providers, to: key, at: i)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
        }
        .background(isToday ? todayTint : Color.clear)
        .modifier(ShakeEffect(shaking: isShaking))
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            ideasPanel
            reminderPanel
        }
    }

    private var horizontalFooter: some View {
        HStack {
            Text("DRAG TO MOVE \u{00B7} SPACE = DONE \u{00B7} \u{232B} = DELETE \u{00B7} ESC = LEAVE")
            Spacer()
            Text("3/DAY \u{00B7} 7-DAY MEMORY")
        }
        .font(captionMono).foregroundColor(footerDim)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("CLICK A LINE \u{00B7} DRAG TO MOVE \u{00B7} SPACE = DONE \u{00B7} \u{232B} = DELETE \u{00B7} ESC = LEAVE")
            Spacer()
            Text("3 PER DAY \u{00B7} 7-DAY MEMORY")
        }
        .font(captionMono).foregroundColor(footerDim)
    }

    // MARK: Date helpers

    private var dateRangeText: String {
        guard let first = viewModel.window.first, let last = viewModel.window.last else { return "" }
        let s = first.firstDate, e = last.lastDate
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "d"
        let mf = DateFormatter(); mf.locale = Locale(identifier: "en_US_POSIX"); mf.dateFormat = "MMM"
        let sm = mf.string(from: s).uppercased(), em = mf.string(from: e).uppercased()
        if sm == em { return "\(df.string(from: s)) \u{2013} \(df.string(from: e)) \(sm)" }
        return "\(df.string(from: s)) \(sm) \u{2013} \(df.string(from: e)) \(em)"
    }
}

// MARK: - ShakeEffect

private struct ShakeEffect: ViewModifier {
    var shaking: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        content
            .offset(x: reduceMotion ? 0 : offset)
            .onChange(of: shaking) { newValue in
                guard newValue, !reduceMotion else { offset = 0; return }
                let steps: [(CGFloat, Double)] = [(5, 0.04), (-5, 0.08), (4, 0.12), (-3, 0.16), (0, 0.20)]
                for (x, delay) in steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { offset = x }
                }
            }
    }
}

// MARK: - UndoToast

private struct UndoToast: View {
    let onUndo: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("Deleted").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.9))
            Button("Undo") { onUndo() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.black.opacity(0.75)).cornerRadius(6)
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rh: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += rh + spacing; rh = 0 }
            rh = max(rh, s.height); x += s.width + spacing
        }
        return CGSize(width: w, height: y + rh)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rh: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.width, x > 0 { x = 0; y += rh + spacing; rh = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            rh = max(rh, s.height); x += s.width + spacing
        }
    }
}

// MARK: - Mock data

extension Sheet {
    static let mock: Sheet = {
        var sheet = Sheet(
            buckets: [
                BucketKey("2026-09-21")!: [Item(text: "Ship spec v0.1", done: true), Item(text: "Call with Ana")],
                BucketKey("2026-09-22")!: [Item(text: "Rewrite onboarding copy")],
                BucketKey("2026-09-23")!: [Item(text: "Dentist, 14:30"), Item(text: "Invoice August"), Item(text: "Read Nagel essay")],
                BucketKey("2026-09-24")!: [Item(text: "Widget window layer"), Item(text: "Groceries")],
                BucketKey("2026-09-25")!: [Item(text: "Week review")],
                BucketKey("2026-09-26")!: [Item(text: "Bike to the reservoir")]
            ],
            ideas: [
                Item(text: "Look into SMAppService"),
                Item(text: "Cancel the storage unit"),
                Item(text: "Birthday present for M."),
                Item(text: "Fix the bathroom light")
            ],
            weeklyFocus: [:]
        )
        sheet.setFocus("Rent, Tuesday", for: Sheet.parseDate("2026-09-21")!)
        return sheet
    }()
}
