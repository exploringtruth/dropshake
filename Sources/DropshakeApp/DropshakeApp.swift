import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct DropshakeApp: App {
    @StateObject private var shelf = ShelfStore()

    var body: some Scene {
        WindowGroup("Dropshake") {
            ShelfView(store: shelf)
                .frame(minWidth: 360, minHeight: 280)
                .background(.ultraThinMaterial)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("Dropshake", systemImage: "tray.and.arrow.down") {
            Button("Open Shelf") { NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut("o")
            Button("Clear Shelf") { shelf.clear() }
            Divider()
            Button("Quit Dropshake") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
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
            Button { store.clear() } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered).controlSize(.small).help("Drop files onto the shelf to add them")
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
