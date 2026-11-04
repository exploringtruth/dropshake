import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct DropshakeApp: App {
    @StateObject private var runtime = DropshakeRuntime()

    var body: some Scene {
        MenuBarExtra("Dropshake", systemImage: "tray.and.arrow.down") {
            Button("Open Shelf") { runtime.showShelf() }
                .keyboardShortcut("o")
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

        shakeDetector.onShake = { [weak shelfWindow] in
            shelfWindow?.show(near: NSEvent.mouseLocation)
        }
        shakeDetector.isEnabled = shakeEnabled
        shakeDetector.start()
    }

    func showShelf() { shelfWindow.show(near: nil) }
    func hideShelf() { shelfWindow.hide() }

    func toggleShake() {
        shakeEnabled.toggle()
        UserDefaults.standard.set(shakeEnabled, forKey: shakeEnabledKey)
        shakeDetector.isEnabled = shakeEnabled
    }
}

@MainActor
final class ShelfWindowController {
    private let store: ShelfStore
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 380, height: 330)

    init(store: ShelfStore) { self.store = store }

    func show(near point: NSPoint?) {
        let panel = makePanelIfNeeded()
        let target = point ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(target) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: panelSize)
        let origin = NSPoint(
            x: min(max(target.x + 18, visibleFrame.minX), visibleFrame.maxX - panelSize.width),
            y: min(max(target.y - panelSize.height / 2, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: ShelfView(store: store, onClose: { [weak self] in self?.hide() })
                .frame(width: panelSize.width, height: panelSize.height)
        )
        self.panel = panel
        return panel
    }
}

@MainActor
final class ShakeDetector {
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

    private enum Axis { case horizontal, vertical }

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

        if timestamp - gestureStart > 0.7 {
            resetGesture(at: timestamp, point: previous)
        }
        guard step >= 3 else { return }

        let axis: Axis = abs(deltaX) >= abs(deltaY) ? .horizontal : .vertical
        let direction = axis == .horizontal ? (deltaX > 0 ? 1 : -1) : (deltaY > 0 ? 1 : -1)
        if axis == previousAxis, direction != previousDirection { reversals += 1 }
        previousAxis = axis
        previousDirection = direction
        distance += step

        if reversals >= 3, distance >= 72, timestamp - gestureStart <= 0.7 {
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
    var text: String?

    init(fileURL: URL) { self.id = UUID(); self.fileURL = fileURL; self.text = nil }
    init(text: String) { self.id = UUID(); self.fileURL = nil; self.text = text }
    var name: String {
        if let fileURL { return fileURL.lastPathComponent }
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Text"
        return value.isEmpty ? "Text" : String(value.prefix(48))
    }
    var kind: String {
        guard let fileURL else { return (text?.hasPrefix("http") == true) ? "Link" : "Text" }
        return fileURL.hasDirectoryPath ? "Folder" : fileURL.pathExtension.uppercased().isEmpty ? "File" : fileURL.pathExtension.uppercased()
    }
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    private let storageKey = "dropshake.shelf.items"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.filter { item in
                guard let fileURL = item.fileURL else { return item.text != nil }
                return FileManager.default.fileExists(atPath: fileURL.path)
            }
        }
    }

    func add(fileURL: URL) {
        guard !items.contains(where: { $0.fileURL == fileURL }) else { return }
        items.append(ShelfItem(fileURL: fileURL))
        save()
    }

    func add(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !items.contains(where: { $0.text == clean }) else { return }
        items.append(ShelfItem(text: clean))
        save()
    }

    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id }; save() }
    func clear() { items.removeAll(); save() }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    let onClose: () -> Void
    @State private var isTargeted = false

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
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $isTargeted, perform: acceptDrop)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dropshake").font(.headline)
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
        .padding(.horizontal, 18).padding(.vertical, 14)
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
        VStack(spacing: 7) {
            if let fileURL = item.fileURL {
                FileIcon(url: fileURL).frame(height: 48)
            } else {
                Image(systemName: item.kind == "Link" ? "link" : "text.alignleft")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(.tint).frame(height: 48)
            }
            Text(item.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            Text(item.kind).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Button { store.remove(item) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray.opacity(0.8))
            }
            .buttonStyle(.plain).padding(5).opacity(0.85)
        }
        .onDrag {
            if let fileURL = item.fileURL { return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: item.name as NSString) }
            return NSItemProvider(object: (item.text ?? item.name) as NSString)
        }
        .help("Drag \(item.name) out of the shelf")
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

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let accepted = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        guard !accepted.isEmpty else { return false }
        for provider in accepted {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in store.add(fileURL: url) }
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in store.add(text: url.absoluteString) }
                }
            } else {
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value else { return }
                    Task { @MainActor in store.add(text: value) }
                }
            }
        }
        return true
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
