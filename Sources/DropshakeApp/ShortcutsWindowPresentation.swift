import AppKit
import SwiftUI

// Uses the window ordering and single focus recovery described by Clipbara's
// SettingsWindowFront: https://github.com/mobrava/Clipbara/blob/4bfc04dce7cf45188da76cbf7cb07006e4794b61/Clipbara/Views/Settings/SettingsWindowFront.swift
@MainActor
final class ShortcutsWindowPresentation {
    static let shared = ShortcutsWindowPresentation()

    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutPreferencesView()))
        window.title = "Shortcuts"
        window.styleMask.remove(.resizable)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        window.center()
        return window
    }()
    private var presentation: Task<Void, Never>?
    private var needsFocusRecovery = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverFocusIfNeeded() }
        }
    }

    func bringForward() {
        presentation?.cancel()
        needsFocusRecovery = true
        presentation = Task {
            do {
                try await Task.sleep(for: .milliseconds(1500))
            } catch {
                return
            }
            needsFocusRecovery = false
            window.level = .normal
            presentation = nil
        }

        activate()
        raiseWindow()
        DispatchQueue.main.async { [weak self] in
            guard self?.window.isVisible == true else { return }
            self?.raiseWindow()
        }
    }

    private func recoverFocusIfNeeded() {
        guard needsFocusRecovery, window.isVisible else { return }
        needsFocusRecovery = false
        activate()
        raiseWindow()
    }

    private func raiseWindow() {
        guard presentation != nil else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func activate() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
