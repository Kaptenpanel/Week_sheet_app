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
    @Published var week: Week
    @Published var isEditMode = false
    @Published var selectedID: UUID?
    @Published var editingID: UUID?
    @Published var addingDay: Day?
    @Published var addingIdea = false
    @Published var editingReminder = false
    @Published var editingNotes = false
    @Published private(set) var undoState: UndoInfo?
    @Published var shakingDay: Day?
    @Published var isHorizontalMode: Bool

    let store: FileStore
    private var eventMonitor: Any?
    private var undoTimer: Timer?
    private var resetTimer: Timer?

    struct UndoInfo { let item: Item; let day: Day?; let position: Int }

    public init(store: FileStore) {
        self.store = store
        self.isHorizontalMode = UserDefaults.standard.bool(forKey: "horizontalMode")
        self.week = (try? store.loadAndResetIfNeeded()) ?? Week.empty(weekStart: Week.mondayOfWeek(containing: Date()))
        resetTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkReset()
        }
    }

    deinit {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        undoTimer?.invalidate()
        resetTimer?.invalidate()
    }

    private func save() { try? store.save(week) }

    func checkReset() {
        guard week.needsReset() else { return }
        if let w = try? store.loadAndResetIfNeeded() { week = w }
    }

    func addItem(to day: Day, text: String) {
        addingDay = nil
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        _ = try? week.addItem(to: day, text: t)
        save()
    }

    func addIdea(text: String) {
        addingIdea = false
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        week.addIdea(text: t)
        save()
    }

    func toggleDone() {
        guard let id = selectedID else { return }
        if week.ideas.contains(where: { $0.id == id }) { return }
        try? week.toggleDone(id)
        save()
    }

    func deleteItem(_ id: UUID) {
        var foundItem: Item?
        var foundDay: Day?
        var foundPos = 0
        for day in Day.allCases {
            if let idx = week.days[day]?.firstIndex(where: { $0.id == id }) {
                foundItem = week.days[day]![idx]; foundDay = day; foundPos = idx; break
            }
        }
        if foundItem == nil, let idx = week.ideas.firstIndex(where: { $0.id == id }) {
            foundItem = week.ideas[idx]; foundPos = idx
        }
        guard let item = foundItem else { return }
        try? week.deleteItem(id)
        if selectedID == id { selectedID = nil }
        save()
        undoTimer?.invalidate()
        undoState = UndoInfo(item: item, day: foundDay, position: foundPos)
        undoTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.undoState = nil }
        }
    }

    func undo() {
        guard let info = undoState else { return }
        undoTimer?.invalidate()
        undoState = nil
        if let day = info.day {
            let items = week.days[day, default: []]
            if items.count < Week.maxItemsPerDay {
                week.days[day, default: []].insert(info.item, at: min(info.position, items.count))
            } else {
                week.ideas.append(info.item)
            }
        } else {
            week.ideas.insert(info.item, at: min(info.position, week.ideas.count))
        }
        save()
    }

    func updateText(_ id: UUID, newText: String) {
        editingID = nil
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        for day in Day.allCases {
            if let idx = week.days[day]?.firstIndex(where: { $0.id == id }) {
                week.days[day]![idx].text = t; save(); return
            }
        }
        if let idx = week.ideas.firstIndex(where: { $0.id == id }) {
            week.ideas[idx].text = t; save()
        }
    }

    func select(_ id: UUID?) {
        if editingID != nil { editingID = nil }
        selectedID = id
        if addingDay != nil { addingDay = nil }
        if addingIdea { addingIdea = false }
    }

    func startAddingToDay(_ day: Day) {
        guard week.days[day, default: []].count < Week.maxItemsPerDay else { return }
        addingDay = day; editingID = nil; selectedID = nil
    }

    func startAddingIdea() { addingIdea = true; editingID = nil; selectedID = nil }

    func startEditing(_ id: UUID) { editingID = id; selectedID = id }

    func startEditingReminder() { editingReminder = true; editingNotes = false; editingID = nil; selectedID = nil; addingDay = nil; addingIdea = false }

    func updateReminder(_ text: String) {
        editingReminder = false
        week.reminder = text.trimmingCharacters(in: .whitespaces)
        save()
    }

    func startEditingNotes() { editingNotes = true; editingReminder = false; editingID = nil; selectedID = nil; addingDay = nil; addingIdea = false }

    func updateNotes(_ text: String) {
        editingNotes = false
        week.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func moveItemToDay(_ id: UUID, day: Day, position: Int) {
        do {
            try week.moveItem(id, to: day, at: position)
            save()
        } catch WeekError.dayFull {
            shakingDay = day
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if self?.shakingDay == day { self?.shakingDay = nil }
            }
        } catch {}
    }

    func moveItemToIdeas(_ id: UUID) {
        try? week.moveToIdeas(id)
        save()
    }

    func cancelEditing() { editingID = nil; addingDay = nil; addingIdea = false; editingReminder = false; editingNotes = false; selectedID = nil }

    func toggleLayoutMode() {
        isHorizontalMode.toggle()
        UserDefaults.standard.set(isHorizontalMode, forKey: "horizontalMode")
    }

    // MARK: Key handler

    func installKeyHandler() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.editingID != nil || self.addingDay != nil || self.addingIdea { return event }
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

// MARK: - InlineTextEditor (multi-line)

private struct InlineTextEditor: NSViewRepresentable {
    let text: String
    let onCommit: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.string = text
        tv.font = .systemFont(ofSize: 12)
        tv.textColor = .black
        tv.isRichText = false
        tv.backgroundColor = .clear
        tv.isEditable = true
        tv.isSelectable = true
        tv.delegate = context.coordinator
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.textContainer?.widthTracksTextView = true

        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = false
        sv.drawsBackground = false
        sv.borderType = .noBorder

        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    class Coordinator: NSObject, NSTextViewDelegate {
        let onCommit: (String) -> Void
        init(onCommit: @escaping (String) -> Void) { self.onCommit = onCommit }

        func textDidEndEditing(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onCommit(tv.string)
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
            ForEach(Day.allCases, id: \.self) { day in
                dayColumn(day).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: Day) -> some View {
        let items = viewModel.week.days[day, default: []]
        let isToday = (day == todayDay)
        let isShaking = viewModel.shakingDay == day

        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(isToday ? todayBar : Color.clear).frame(height: 2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(day.rawValue.uppercased()).font(headerFont)
                Text(dateLabelFor(day)).font(smallMono)
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
                    } else if viewModel.addingDay == day && i == items.count {
                        InlineTextField(
                            text: "",
                            onCommit: { viewModel.addItem(to: day, text: $0) },
                            onCancel: { viewModel.addingDay = nil }
                        ).frame(height: 28)
                    } else {
                        Rectangle().fill(Color.clear).frame(height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.startAddingToDay(day) }
                    }
                    Rectangle().fill(ruleColor).frame(height: 1)
                }
                .padding(.horizontal, 8)
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleDrop(providers, to: day, at: i)
                }
            }
        }
        .background(isToday ? todayTint : Color.clear)
        .modifier(ShakeEffect(shaking: isShaking))
    }

    private func handleDrop(_ providers: [NSItemProvider], to day: Day, at position: Int) -> Bool {
        guard viewModel.isEditMode else { return false }
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidString = string as? String, let id = UUID(uuidString: uuidString) else { return }
            DispatchQueue.main.async { self.viewModel.moveItemToDay(id, day: day, position: position) }
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
            VStack(spacing: 12) { reminderPanel; notesPanel }
        }
    }

    private var ideasPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEW IDEAS").font(headerFont).foregroundColor(.black.opacity(0.6))
                Text("\(viewModel.week.ideas.count)").font(smallMono).foregroundColor(labelDim)
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
                ForEach(viewModel.week.ideas) { idea in
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
                Text(viewModel.week.reminder.isEmpty ? " " : viewModel.week.reminder)
                    .font(bodyFont).foregroundColor(bodyText)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    .opacity(viewModel.editingReminder ? 0 : 1)
                if viewModel.editingReminder && viewModel.isEditMode {
                    InlineTextField(
                        text: viewModel.week.reminder,
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

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES").font(headerFont).foregroundColor(.black.opacity(0.6))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        Spacer().frame(height: 20)
                        Rectangle().fill(ruleColor.opacity(0.5)).frame(height: 1)
                    }
                }
                Text(viewModel.week.notes.isEmpty ? " " : viewModel.week.notes)
                    .font(bodyFont).foregroundColor(bodyText).lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .opacity(viewModel.editingNotes ? 0 : 1)
                if viewModel.editingNotes && viewModel.isEditMode {
                    InlineTextEditor(
                        text: viewModel.week.notes,
                        onCommit: { viewModel.updateNotes($0) }
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.isEditMode && !viewModel.editingNotes { viewModel.startEditingNotes() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(coolPanel).cornerRadius(4)
    }

    // MARK: Horizontal layout

    private var dayRows: some View {
        VStack(spacing: 0) {
            ForEach(Day.allCases, id: \.self) { day in
                dayRow(day)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dayRow(_ day: Day) -> some View {
        let items = viewModel.week.days[day, default: []]
        let isToday = (day == todayDay)
        let isShaking = viewModel.shakingDay == day

        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(isToday ? todayBar : Color.clear).frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(day.rawValue.uppercased()).font(headerFont)
                Text(horizontalDateLabel(day)).font(smallMono)
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
                        } else if viewModel.addingDay == day && i == items.count {
                            InlineTextField(
                                text: "",
                                onCommit: { viewModel.addItem(to: day, text: $0) },
                                onCancel: { viewModel.addingDay = nil }
                            ).frame(height: 28)
                        } else {
                            Rectangle().fill(Color.clear).frame(height: 28)
                                .contentShape(Rectangle())
                                .onTapGesture { viewModel.startAddingToDay(day) }
                        }
                        Rectangle().fill(ruleColor).frame(height: 1)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        handleDrop(providers, to: day, at: i)
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
            notesPanel
            reminderPanel
        }
    }

    private var horizontalFooter: some View {
        HStack {
            Text("DRAG TO MOVE \u{00B7} SPACE = DONE \u{00B7} \u{232B} = DELETE \u{00B7} ESC = LEAVE")
            Spacer()
            Text("3/DAY \u{00B7} RESETS MON 04:00")
        }
        .font(captionMono).foregroundColor(footerDim)
    }

    private func horizontalDateLabel(_ day: Day) -> String {
        guard let s = weekStartDate else { return "" }
        let cal = Calendar.current
        let mf = DateFormatter()
        mf.locale = Locale(identifier: "en_US_POSIX")
        mf.dateFormat = "d MMM"
        if day == .wknd {
            let sat = cal.date(byAdding: .day, value: 5, to: s)!
            let sun = cal.date(byAdding: .day, value: 6, to: s)!
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "d"
            let monthF = DateFormatter()
            monthF.locale = Locale(identifier: "en_US_POSIX")
            monthF.dateFormat = "MMM"
            return "\(df.string(from: sat))-\(df.string(from: sun)) \(monthF.string(from: sat).uppercased())"
        }
        let off: Int
        switch day {
        case .mon: off = 0; case .tue: off = 1; case .wed: off = 2
        case .thu: off = 3; case .fri: off = 4; default: off = 0
        }
        let date = cal.date(byAdding: .day, value: off, to: s)!
        return mf.string(from: date).uppercased()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("CLICK A LINE \u{00B7} DRAG TO MOVE \u{00B7} SPACE = DONE \u{00B7} \u{232B} = DELETE \u{00B7} ESC = LEAVE")
            Spacer()
            Text("3 PER DAY \u{00B7} RESETS MON 04:00")
        }
        .font(captionMono).foregroundColor(footerDim)
    }

    // MARK: Date helpers

    private var weekStartDate: Date? { Week.parseDate(viewModel.week.weekStart) }

    private var dateRangeText: String {
        guard let s = weekStartDate,
              let e = Calendar.current.date(byAdding: .day, value: 6, to: s) else { return "" }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "d"
        let mf = DateFormatter(); mf.locale = Locale(identifier: "en_US_POSIX"); mf.dateFormat = "MMM"
        let sm = mf.string(from: s).uppercased(), em = mf.string(from: e).uppercased()
        if sm == em { return "\(df.string(from: s)) \u{2013} \(df.string(from: e)) \(sm)" }
        return "\(df.string(from: s)) \(sm) \u{2013} \(df.string(from: e)) \(em)"
    }

    private func dateLabelFor(_ day: Day) -> String {
        guard let s = weekStartDate else { return "" }
        let cal = Calendar.current
        if day == .wknd {
            let sat = cal.date(byAdding: .day, value: 5, to: s)!
            let sun = cal.date(byAdding: .day, value: 6, to: s)!
            return "\(cal.component(.day, from: sat))/\(cal.component(.day, from: sun))"
        }
        let off: Int
        switch day {
        case .mon: off = 0; case .tue: off = 1; case .wed: off = 2
        case .thu: off = 3; case .fri: off = 4; default: off = 0
        }
        return String(format: "%02d", cal.component(.day, from: cal.date(byAdding: .day, value: off, to: s)!))
    }

    private var todayDay: Day? {
        guard let s = weekStartDate else { return nil }
        let diff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: s), to: Calendar.current.startOfDay(for: Date())).day ?? -1
        switch diff {
        case 0: return .mon; case 1: return .tue; case 2: return .wed
        case 3: return .thu; case 4: return .fri; case 5, 6: return .wknd; default: return nil
        }
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

extension Week {
    static let mock = Week(
        weekStart: "2026-08-31",
        days: [
            .mon: [Item(text: "Ship spec v0.1", done: true), Item(text: "Call with Ana")],
            .tue: [Item(text: "Rewrite onboarding copy")],
            .wed: [Item(text: "Dentist, 14:30"), Item(text: "Invoice August"), Item(text: "Read Nagel essay")],
            .thu: [Item(text: "Widget window layer"), Item(text: "Groceries")],
            .fri: [Item(text: "Week review")],
            .wknd: [Item(text: "Bike to the reservoir")]
        ],
        ideas: [
            Item(text: "Look into SMAppService"),
            Item(text: "Cancel the storage unit"),
            Item(text: "Birthday present for M."),
            Item(text: "Fix the bathroom light")
        ],
        reminder: "Rent, Tuesday",
        notes: "Cap of 3 is the product.\nDon't add a fourth slot."
    )
}
