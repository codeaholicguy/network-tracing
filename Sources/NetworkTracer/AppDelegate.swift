import AppKit
import SwiftUI
import NetworkTracerCore

// T1.3, T1.4: NSStatusItem + NSPopover wiring
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = ConnectionStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        Task { await NetworkMonitor.shared.start(store: store) }
    }

    // T1.3: menubar icon
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Network Monitor")
        button.action = #selector(togglePopover)
        button.target = self
        // T4.7: tooltip with connection count is driven by observing store in updateTooltip
        updateTooltip()
    }

    // T1.4: popover setup
    private func setupPopover() {
        let contentView = PopoverView()
            .environmentObject(store)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updateTooltip()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // T4.7: refresh tooltip each time popover opens
    private func updateTooltip() {
        let count = store.connections.count
        statusItem.button?.toolTip = "\(count) active connection\(count == 1 ? "" : "s")"
    }
}
