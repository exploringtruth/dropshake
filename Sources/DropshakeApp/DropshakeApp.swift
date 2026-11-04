import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct DropshakeApp: App {
    @StateObject private var runtime = DropshakeRuntime()

    var body: some Scene {
        MenuBarExtra("Dropshake", systemImage: "tray.and.arrow.down") {
            Button("Open Shelf") { runtime.showShelf() }
                .keyboardShortcut("o")
            Button("Add Clipboard Contents") { runtime.captureClipboard() }
            Button("Hide Shelf") { runtime.hideShelf() }
            Button("Clear Shelf") { runtime.shelf.clear() }
            Divider()
            Button(runtime.shakeEnabled ? "Disable Shake to Open" : "Enable Shake to Open") {
                runtime.toggleShake()
            }
            Divider()
            Button("Quit Dropshake") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class DropshakeRuntime: ObservableObject {
    let shelf = ShelfStore()
    private let shelfWindow: ShelfWindowController
    private let shakeDetector: ShakeDetector
    @Published private(set) var shakeEnabled: Bool

    private let shakeEnabledKey = "dropshake.shakeEnabled"

    init() {
        let shelfWindow = ShelfWindowController(store: shelf)
        let shakeDetector = ShakeDetector()
        self.shelfWindow = shelfWindow
        self.shakeDetector = shakeDetector
        self.shakeEnabled = UserDefaults.standard.object(forKey: shakeEnabledKey) as? Bool ?? true

        shakeDetector.onShake = { [weak self, weak shelfWindow] in
            self?.shelf.clear()
            shelfWindow?.show(near: NSEvent.mouseLocation, resetToDefaultSize: true)
        }
        shakeDetector.isEnabled = shakeEnabled
        shakeDetector.start()
    }

    func showShelf() { shelfWindow.show(near: nil) }
    func hideShelf() { shelfWindow.hide() }
    func captureClipboard() {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? []
        if !urls.isEmpty {
            for value in urls {
                let url = value as URL
                if url.isFileURL { shelf.add(fileURL: url) }
                else { shelf.add(text: url.absoluteString) }
            }
        } else if let text = pasteboard.string(forType: .string) {
            shelf.add(text: text)
        }
        shelfWindow.show(near: nil)
    }

    func toggleShake() {
        shakeEnabled.toggle()
        UserDefaults.standard.set(shakeEnabled, forKey: shakeEnabledKey)
        shakeDetector.isEnabled = shakeEnabled
    }
}

@MainActor
final class ShelfWindowController: NSObject, NSWindowDelegate {
    private let store: ShelfStore
    private var panel: NSPanel?
    private let defaultPanelSize = NSSize(width: 380, height: 330)
    private let minimumPanelSize = NSSize(width: 300, height: 240)
    private let savedWidthKey = "dropshake.shelfWindow.width"
    private let savedHeightKey = "dropshake.shelfWindow.height"

    init(store: ShelfStore) {
        self.store = store
        super.init()
    }

    func show(near point: NSPoint?, resetToDefaultSize: Bool = false) {
        let panel = makePanelIfNeeded()
        if resetToDefaultSize {
            panel.setContentSize(defaultPanelSize)
            UserDefaults.standard.set(Double(defaultPanelSize.width), forKey: savedWidthKey)
            UserDefaults.standard.set(Double(defaultPanelSize.height), forKey: savedHeightKey)
        }
        let size = panel.frame.size
        let target = point ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: defaultPanelSize)
        let origin = NSPoint(
            x: min(max(target.x + 18, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(target.y - size.height / 2, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        (panel?.contentView as? ShelfResizeCursorManaging)?.clearHoverCursor()
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let savedWidth = UserDefaults.standard.double(forKey: savedWidthKey)
        let savedHeight = UserDefaults.standard.double(forKey: savedHeightKey)
        let initialSize = NSSize(
            width: max(minimumPanelSize.width, savedWidth == 0 ? defaultPanelSize.width : savedWidth),
            height: max(minimumPanelSize.height, savedHeight == 0 ? defaultPanelSize.height : savedHeight)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = minimumPanelSize
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = ResizableShelfHostingView(
            rootView: ShelfView(store: store, onClose: { [weak self] in self?.hide() })
                .frame(
                    minWidth: minimumPanelSize.width,
                    maxWidth: .infinity,
                    minHeight: minimumPanelSize.height,
                    maxHeight: .infinity
                )
        )
        self.panel = panel
        return panel
    }

    func windowDidResize(_ notification: Notification) {
        guard let resizedPanel = notification.object as? NSWindow,
              resizedPanel === panel else { return }
        UserDefaults.standard.set(Double(resizedPanel.frame.width), forKey: savedWidthKey)
        UserDefaults.standard.set(Double(resizedPanel.frame.height), forKey: savedHeightKey)
    }
}

@MainActor
final class ShakeDetector {
    private let gestureWindow: TimeInterval = 0.4
    private let minimumShakeDistance: Double = 30
    private let minimumDirectionReversals = 2

    var onShake: (() -> Void)?
    var isEnabled = true

    private var monitor: Any?
    private var isDragging = false
    private var hasTriggered = false
    private var lastPoint: NSPoint?
    private var gestureStart: TimeInterval = 0
    private var previousAxis: Axis?
    private var previousDirection = 0
    private var reversals = 0
    private var distance = 0.0

    private enum Axis: Equatable { case horizontal, vertical }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            let type = event.type
            let timestamp = event.timestamp
            let point = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.handle(type: type, timestamp: timestamp, point: point)
            }
        }
    }

    private func handle(type: NSEvent.EventType, timestamp: TimeInterval, point: NSPoint) {
        switch type {
        case .leftMouseDown:
            isDragging = true
            resetGesture(at: timestamp, point: point)
            hasTriggered = false
        case .leftMouseUp:
            isDragging = false
            lastPoint = nil
            hasTriggered = false
        case .leftMouseDragged:
            guard isEnabled, isDragging, !hasTriggered else { return }
            track(point: point, timestamp: timestamp)
        default:
            break
        }
    }

    private func track(point: NSPoint, timestamp: TimeInterval) {
        guard let previous = lastPoint else {
            resetGesture(at: timestamp, point: point)
            return
        }

        let deltaX = point.x - previous.x
        let deltaY = point.y - previous.y
        let step = hypot(deltaX, deltaY)
        lastPoint = point

        if timestamp - gestureStart > gestureWindow {
            resetGesture(at: timestamp, point: previous)
        }
        guard step >= 3 else { return }

        let axis: Axis = abs(deltaX) >= abs(deltaY) ? .horizontal : .vertical
        let direction = axis == .horizontal ? (deltaX > 0 ? 1 : -1) : (deltaY > 0 ? 1 : -1)
        if axis == previousAxis, direction != previousDirection { reversals += 1 }
        previousAxis = axis
        previousDirection = direction
        distance += step

        if reversals >= minimumDirectionReversals,
           distance >= minimumShakeDistance,
           timestamp - gestureStart <= gestureWindow {
            hasTriggered = true
            onShake?()
        }
    }

    private func resetGesture(at timestamp: TimeInterval, point: NSPoint) {
        gestureStart = timestamp
        lastPoint = point
        previousAxis = nil
        previousDirection = 0
        reversals = 0
        distance = 0
    }
}

struct ShelfItem: Identifiable, Codable, Equatable {
    var id: UUID
    var fileURL: URL?
    var bookmarkData: Data?
    var text: String?

    init(fileURL: URL) {
        self.id = UUID()
        self.fileURL = fileURL
        self.bookmarkData = try? fileURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        self.text = nil
    }
    init(text: String) { self.id = UUID(); self.fileURL = nil; self.bookmarkData = nil; self.text = text }

    mutating func resolveFileURL() -> URL? {
        guard let fileURL else { return nil }
        guard let bookmarkData else { return fileURL }
        var isStale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return fileURL
        }
        self.fileURL = resolved
        if isStale {
            self.bookmarkData = try? resolved.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return resolved
    }
    var name: String {
        if let fileURL { return fileURL.lastPathComponent }
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Text"
        return value.isEmpty ? "Text" : String(value.prefix(48))
    }
    var kind: String {
        guard let fileURL else { return (text?.hasPrefix("http") == true) ? "Link" : "Text" }
        return fileURL.hasDirectoryPath ? "Folder" : fileURL.pathExtension.uppercased().isEmpty ? "File" : fileURL.pathExtension.uppercased()
    }

    private enum CodingKeys: String, CodingKey { case id, fileURL, url, bookmarkData, text }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        let currentURL = try values.decodeIfPresent(URL.self, forKey: .fileURL)
        let olderURL = try values.decodeIfPresent(URL.self, forKey: .url)
        fileURL = currentURL ?? olderURL
        bookmarkData = try values.decodeIfPresent(Data.self, forKey: .bookmarkData)
        text = try values.decodeIfPresent(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(fileURL, forKey: .fileURL)
        try values.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try values.encodeIfPresent(text, forKey: .text)
    }
}

struct Shelf: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var items: [ShelfItem]

    init(id: UUID = UUID(), name: String, items: [ShelfItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var shelves: [Shelf]
    @Published private(set) var activeShelfID: UUID

    private let storageKey = "dropshake.shelves.v1"
    private let activeShelfKey = "dropshake.activeShelfID"
    private let legacyStorageKey = "dropshake.shelf.items"

    var items: [ShelfItem] {
        shelves.first(where: { $0.id == activeShelfID })?.items ?? []
    }

    var activeShelfName: String {
        shelves.first(where: { $0.id == activeShelfID })?.name ?? "Shelf"
    }

    init() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()
        let savedShelves = defaults.data(forKey: storageKey)
            .flatMap { try? decoder.decode([Shelf].self, from: $0) } ?? []
        let migratedItems = defaults.data(forKey: legacyStorageKey)
            .flatMap { try? decoder.decode([ShelfItem].self, from: $0) } ?? []
        let savedID = defaults.string(forKey: activeShelfKey).flatMap(UUID.init(uuidString:))
        let currentShelf = savedShelves.first(where: { $0.id == savedID })
            ?? savedShelves.first
            ?? Shelf(name: "Shelf", items: migratedItems)
        let currentItems = currentShelf.items.compactMap { original -> ShelfItem? in
            var item = original
            guard let fileURL = item.resolveFileURL() else { return item.text == nil ? nil : item }
            return FileManager.default.fileExists(atPath: fileURL.path) ? item : nil
        }
        let retainedShelf = Shelf(id: currentShelf.id, name: "Shelf", items: currentItems)
        self.shelves = [retainedShelf]
        self.activeShelfID = retainedShelf.id
        save()
    }

    func add(fileURL: URL) {
        guard let index = activeIndex,
              !shelves[index].items.contains(where: { $0.fileURL == fileURL }) else { return }
        shelves[index].items.append(ShelfItem(fileURL: fileURL))
        save()
    }

    func add(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = activeIndex,
              !clean.isEmpty, !shelves[index].items.contains(where: { $0.text == clean }) else { return }
        shelves[index].items.append(ShelfItem(text: clean))
        save()
    }

    func remove(_ item: ShelfItem) {
        guard let index = activeIndex else { return }
        shelves[index].items.removeAll { $0.id == item.id }
        save()
    }

    func removeItems(withIDs ids: Set<UUID>) {
        guard let index = activeIndex, !ids.isEmpty else { return }
        shelves[index].items.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        guard let index = activeIndex else { return }
        shelves[index].items.removeAll()
        save()
    }

    private var activeIndex: Int? { shelves.firstIndex(where: { $0.id == activeShelfID }) }

    private func save() {
        guard let shelvesData = try? JSONEncoder().encode(shelves) else { return }
        let defaults = UserDefaults.standard
        defaults.set(shelvesData, forKey: storageKey)
        defaults.set(activeShelfID.uuidString, forKey: activeShelfKey)
    }
}

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    let onClose: () -> Void
    @State private var isTargeted = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.items.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.items) { item in itemCard(item) }
                    }
                    .padding(16)
                }
            }
            footer
        }
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .background(ShelfDropTarget(
            isTargeted: $isTargeted,
            onFileURL: { store.add(fileURL: $0) },
            onURL: { url in
                if url.isFileURL { store.add(fileURL: url) }
                else { store.add(text: url.absoluteString) }
            },
            onText: { store.add(text: $0) }
        ))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                .help("Drag anywhere across the header to move shelf")
            Image(systemName: "tray.full.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shelf").font(.headline)
                Text(store.items.isEmpty ? "Your temporary shelf" : "\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.items.isEmpty {
                Button(action: store.clear) { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Clear shelf")
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Hide shelf")
        }
        .padding(.horizontal, 30).padding(.vertical, 14)
        .background(WindowDragHandle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text("Drop files, links, or text here")
                .font(.system(size: 14, weight: .medium))
            Text("Drag them out whenever you’re ready.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func itemCard(_ item: ShelfItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)
        let dragItems = isSelected
            ? store.items.filter { selectedItemIDs.contains($0.id) && $0.fileURL != nil }
            : [item]

        let content = VStack(spacing: 7) {
            if let fileURL = item.fileURL {
                FileIcon(url: fileURL).frame(height: 48).allowsHitTesting(false)
            } else {
                Image(systemName: item.kind == "Link" ? "link" : "text.alignleft")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(.tint).frame(height: 48)
            }
            Text(item.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            Text(item.kind).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
                .allowsHitTesting(false)
        }

        let selectable: AnyView
        if item.fileURL != nil {
            selectable = AnyView(content.overlay {
                NativeFileDragSource(
                    item: item,
                    dragItems: dragItems,
                    onClick: { select(item, modifiers: $0) },
                    onDroppedOutside: { ids in
                        store.removeItems(withIDs: Set(ids))
                        if store.items.isEmpty { onClose() }
                    }
                )
                .help("Drag anywhere on this card to move the file")
            })
        } else {
            selectable = AnyView(content
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { select(item, modifiers: NSEvent.modifierFlags) }
                .onDrag { NSItemProvider(object: (item.text ?? item.name) as NSString) })
        }

        return AnyView(selectable
        .overlay(alignment: .topTrailing) {
            Button { store.remove(item) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray.opacity(0.8))
            }
            .buttonStyle(.plain).padding(5).opacity(0.85)
        }
        .contextMenu {
            if let fileURL = item.fileURL {
                Button("Quick Look") { QuickLookController.shared.preview(fileURL) }
                Button("Open Item") { NSWorkspace.shared.open(fileURL) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                Button("Copy Path") { copyToClipboard(fileURL.path) }
            } else if let text = item.text {
                Button("Copy Text") { copyToClipboard(text) }
                if let url = URL(string: text), url.scheme != nil {
                    Button("Open Link") { NSWorkspace.shared.open(url) }
                }
            }
            Divider()
            Button("Remove from Shelf") { store.remove(item) }
        }
        .help("Click to select; drag to send to another app"))
    }

    private func select(_ item: ShelfItem, modifiers: NSEvent.ModifierFlags) {
        let visibleItems = store.items
        guard let itemIndex = visibleItems.firstIndex(where: { $0.id == item.id }) else { return }

        if modifiers.contains(.shift),
           let anchorID = selectionAnchorID,
           let anchorIndex = visibleItems.firstIndex(where: { $0.id == anchorID }) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            selectedItemIDs = Set(range.map { visibleItems[$0].id })
        } else if modifiers.contains(.command) {
            if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) }
            else { selectedItemIDs.insert(item.id) }
            selectionAnchorID = item.id
        } else {
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
        }
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var footer: some View {
        HStack {
            Label("Files stay in their original locations", systemImage: "lock.fill")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Text("Shake while dragging to open")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

}

private struct NativeFileDragSource: NSViewRepresentable {
    let item: ShelfItem
    let dragItems: [ShelfItem]
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDroppedOutside: ([UUID]) -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: FileDragSourceView) {
        view.item = item
        view.dragItems = dragItems
        view.onClick = onClick
        view.onDroppedOutside = onDroppedOutside
    }
}

private struct ShelfDropTarget: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onFileURL: (URL) -> Void
    let onURL: (URL) -> Void
    let onText: (String) -> Void

    func makeNSView(context: Context) -> ShelfDropTargetView {
        let view = ShelfDropTargetView()
        update(view)
        return view
    }

    func updateNSView(_ view: ShelfDropTargetView, context: Context) {
        update(view)
    }

    private func update(_ view: ShelfDropTargetView) {
        view.onTargetChange = { isTargeted = $0 }
        view.onFileURL = onFileURL
        view.onURL = onURL
        view.onText = onText
    }
}

private final class ShelfDropTargetView: NSView {
    var onTargetChange: ((Bool) -> Void)?
    var onFileURL: ((URL) -> Void)?
    var onURL: ((URL) -> Void)?
    var onText: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargetChange?(false) }
        let pasteboard = sender.draggingPasteboard
        let readURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] ?? []
        let fileURLs = readURLs.map { $0 as URL }.filter(\.isFileURL)
        if !fileURLs.isEmpty {
            fileURLs.forEach { onFileURL?($0) }
            return true
        }

        let pasteboardFileURLs = (pasteboard.pasteboardItems ?? []).compactMap { item in
            item.string(forType: .fileURL).flatMap(URL.init(string:))
        }.filter(\.isFileURL)
        if !pasteboardFileURLs.isEmpty {
            pasteboardFileURLs.forEach { onFileURL?($0) }
            return true
        }
        if let url = readURLs.first.map({ $0 as URL }) {
            onURL?(url)
            return true
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            onText?(text)
            return true
        }
        return false
    }
}

private final class FileDragSourceView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var dragItems: [ShelfItem] = []
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDroppedOutside: ([UUID]) -> Void = { _ in }
    private var mouseDownPoint: NSPoint?
    private var mouseDownModifiers: NSEvent.ModifierFlags = []
    private var didStartDrag = false
    private var activeDragIDs: [UUID] = []
    private var dragIsExternal = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        mouseDownModifiers = event.modifierFlags
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag,
              let item,
              let mouseDownPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y) >= 4 else { return }

        didStartDrag = true
        let filesToDrag = dragItems.contains(where: { $0.id == item.id }) ? dragItems : [item]
        let fileItems = filesToDrag.filter { $0.fileURL != nil }
        activeDragIDs = fileItems.map(\.id)
        let draggingItems = fileItems.compactMap { shelfItem -> NSDraggingItem? in
            guard let fileURL = shelfItem.fileURL else { return nil }
            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            draggingItem.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(forFile: fileURL.path))
            return draggingItem
        }
        guard !draggingItems.isEmpty else { return }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag, item != nil { onClick?(mouseDownModifiers) }
        mouseDownPoint = nil
        didStartDrag = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        dragIsExternal = context == .outsideApplication
        return NSDragOperation([.copy, .move, .link])
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if dragIsExternal, !operation.isEmpty, !activeDragIDs.isEmpty {
            onDroppedOutside(activeDragIDs)
        }
        activeDragIDs = []
        dragIsExternal = false
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private enum ShelfResizeEdge {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}

private protocol ShelfResizeCursorManaging: AnyObject {
    func clearHoverCursor()
}

private final class ResizableShelfHostingView<Content: View>: NSHostingView<Content>, ShelfResizeCursorManaging {
    private var shelfTrackingArea: NSTrackingArea?
    private var resizeEventMonitor: Any?
    private var hoveredResizeEdge: ShelfResizeEdge?
    private var draggedResizeEdge: ShelfResizeEdge?
    private var hasPushedResizeCursor = false
    private var resizeStartPoint: NSPoint?
    private var resizeStartFrame: NSRect?

    override func updateTrackingAreas() {
        if let shelfTrackingArea { removeTrackingArea(shelfTrackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        shelfTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeEventMonitor { NSEvent.removeMonitor(resizeEventMonitor) }
        resizeEventMonitor = nil
        guard window != nil else { return }
        resizeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleResizeEvent(event) ?? event
        }
    }

    deinit { if let resizeEventMonitor { NSEvent.removeMonitor(resizeEventMonitor) } }

    override func mouseEntered(with event: NSEvent) { updateShelfResizeCursor() }
    override func mouseMoved(with event: NSEvent) { updateShelfResizeCursor() }
    override func mouseExited(with event: NSEvent) { restoreResizeCursor() }

    private func handleResizeEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown {
            guard let window, event.window === window,
                  let edge = resizeEdge(at: screenLocation(for: event)) else { return event }
            draggedResizeEdge = edge
            resizeStartPoint = screenLocation(for: event)
            resizeStartFrame = window.frame
            return nil
        }

        guard let edge = draggedResizeEdge,
              let startPoint = resizeStartPoint,
              let startFrame = resizeStartFrame,
              let window else { return event }

        if event.type == .leftMouseUp {
            draggedResizeEdge = nil
            resizeStartPoint = nil
            resizeStartFrame = nil
            updateShelfResizeCursor()
            return nil
        }

        let point = screenLocation(for: event)
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        var frame = startFrame
        let movesLeft: Bool
        let movesRight: Bool
        let movesBottom: Bool
        let movesTop: Bool
        switch edge {
        case .left: movesLeft = true; movesRight = false; movesBottom = false; movesTop = false
        case .right: movesLeft = false; movesRight = true; movesBottom = false; movesTop = false
        case .bottom: movesLeft = false; movesRight = false; movesBottom = true; movesTop = false
        case .top: movesLeft = false; movesRight = false; movesBottom = false; movesTop = true
        case .topLeft: movesLeft = true; movesRight = false; movesBottom = false; movesTop = true
        case .topRight: movesLeft = false; movesRight = true; movesBottom = false; movesTop = true
        case .bottomLeft: movesLeft = true; movesRight = false; movesBottom = true; movesTop = false
        case .bottomRight: movesLeft = false; movesRight = true; movesBottom = true; movesTop = false
        }

        if movesLeft { frame.origin.x += dx; frame.size.width -= dx }
        if movesRight { frame.size.width += dx }
        if movesBottom { frame.origin.y += dy; frame.size.height -= dy }
        if movesTop { frame.size.height += dy }

        if frame.width < window.minSize.width {
            frame.size.width = window.minSize.width
            if movesLeft { frame.origin.x = startFrame.maxX - window.minSize.width }
        }
        if frame.height < window.minSize.height {
            frame.size.height = window.minSize.height
            if movesBottom { frame.origin.y = startFrame.maxY - window.minSize.height }
        }
        window.setFrame(frame, display: true)
        return nil
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        NSEvent.mouseLocation
    }

    private func resizeEdge(at point: NSPoint) -> ShelfResizeEdge? {
        guard let window else { return nil }
        let frame = window.frame
        let left = point.x <= frame.minX + 5
        let right = point.x >= frame.maxX - 5
        let bottom = point.y <= frame.minY + 5
        let top = point.y >= frame.maxY - 5
        let cornerLeft = point.x <= frame.minX + 24
        let cornerRight = point.x >= frame.maxX - 24
        let cornerBottom = point.y <= frame.minY + 24
        let cornerTop = point.y >= frame.maxY - 24

        if cornerLeft && cornerTop { return .topLeft }
        if cornerRight && cornerTop { return .topRight }
        if cornerLeft && cornerBottom { return .bottomLeft }
        if cornerRight && cornerBottom { return .bottomRight }
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left { return .left }
        if right { return .right }
        if top { return .top }
        if bottom { return .bottom }
        return nil
    }

    private func updateShelfResizeCursor() {
        let edge = resizeEdge(at: NSEvent.mouseLocation)
        guard edge != hoveredResizeEdge else { return }
        restoreResizeCursor()
        guard let edge else { return }
        shelfResizeCursor(at: edge).push()
        hasPushedResizeCursor = true
        hoveredResizeEdge = edge
    }

    private func restoreResizeCursor() {
        if hasPushedResizeCursor { NSCursor.pop() }
        hasPushedResizeCursor = false
        hoveredResizeEdge = nil
    }

    func clearHoverCursor() { restoreResizeCursor() }
}

private func shelfResizeCursor(at edge: ShelfResizeEdge) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edge {
            case .left: position = .left
            case .right: position = .right
            case .top: position = .top
            case .bottom: position = .bottom
            case .topLeft: position = .topLeft
            case .topRight: position = .topRight
            case .bottomLeft: position = .bottomLeft
            case .bottomRight: position = .bottomRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }

        switch edge {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return diagonalResizeCursor(slope: -1)
        case .topRight, .bottomLeft:
            return diagonalResizeCursor(slope: 1)
        }
    }

private func diagonalResizeCursor(slope: CGFloat) -> NSCursor {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size)
        image.lockFocus()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: slope > 0 ? 45 : -45)
        transform.concat()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: -8, y: 0))
        arrow.line(to: NSPoint(x: 8, y: 0))
        arrow.move(to: NSPoint(x: -8, y: 0))
        arrow.line(to: NSPoint(x: -4, y: 4))
        arrow.move(to: NSPoint(x: -8, y: 0))
        arrow.line(to: NSPoint(x: -4, y: -4))
        arrow.move(to: NSPoint(x: 8, y: 0))
        arrow.line(to: NSPoint(x: 4, y: 4))
        arrow.move(to: NSPoint(x: 8, y: 0))
        arrow.line(to: NSPoint(x: 4, y: -4))
        arrow.lineWidth = 2.5
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        NSColor.white.setStroke()
        arrow.lineWidth = 4.5
        arrow.stroke()
        NSColor.black.setStroke()
        arrow.lineWidth = 2
        arrow.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
}

private final class WindowDragView: NSView {
    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialMouseLocation, let initialWindowOrigin, let window else { return }
        let pointer = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: initialWindowOrigin.x + pointer.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + pointer.y - initialMouseLocation.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowOrigin = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

@MainActor
private final class QuickLookController: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookController()
    private var previewItems: [NSURL] = []

    func preview(_ url: URL) {
        previewItems = [url as NSURL]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewItems.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewItems.indices.contains(index) else { return nil }
        return previewItems[index]
    }
}

private struct FileIcon: View {
    let url: URL
    var body: some View {
        Group {
            if let image = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc")
            }
        }
        .padding(2)
    }
}
