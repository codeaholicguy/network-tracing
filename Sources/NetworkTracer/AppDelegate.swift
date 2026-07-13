import AppKit
import Combine
import SwiftUI
import NetworkTracerCore

// T1.3, T1.4: NSStatusItem + NSPopover wiring
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = ConnectionStore.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        Task { await NetworkMonitor.shared.start(store: store) }
    }

    // T1.3: menubar icon
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        observeStore()
        updateStatusItemAppearance()
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
            updateStatusItemAppearance()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func observeStore() {
        store.$connections
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemAppearance() {
        let attentionCount = store.attentionCount
        if attentionCount > 0 {
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.title = ""
            statusItem.button?.image = Self.networkAttentionStatusImage
        } else {
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.title = ""
            statusItem.button?.image = Self.networkStatusImage
        }
        updateTooltip()
    }

    private func updateTooltip() {
        let count = store.connections.count
        let attentionCount = store.attentionCount
        let activeText = "\(count) active connection\(count == 1 ? "" : "s")"
        let attentionText = attentionCount == 0 ? "" : ", \(attentionCount) need attention"
        statusItem.button?.toolTip = "\(activeText)\(attentionText)"
    }

    private static let networkStatusImage = makeNetworkImage()
    private static let networkAttentionStatusImage = makeNetworkAttentionImage()

    private static func makeNetworkImage() -> NSImage {
        let image = NSImage(size: statusIconSize, flipped: false) { _ in
            NSColor.labelColor.set()
            NSImage(
                systemSymbolName: "network",
                accessibilityDescription: "Network Monitor"
            )?.draw(in: networkSymbolRect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func makeNetworkAttentionImage() -> NSImage {
        let image = NSImage(size: statusIconSize, flipped: false) { _ in
            let whiteNetworkImage = NSImage(
                systemSymbolName: "network",
                accessibilityDescription: "Network Monitor"
            )?.withSymbolConfiguration(.init(paletteColors: [.white]))
            whiteNetworkImage?.isTemplate = false
            whiteNetworkImage?.draw(
                in: networkSymbolRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            let emoji = NSAttributedString(
                string: "⚠️",
                attributes: [.font: NSFont.systemFont(ofSize: 10)]
            )
            emoji.draw(in: NSRect(x: 11, y: 0, width: 11, height: 12))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Network Monitor, connections need attention"
        return image
    }

    private static let statusIconSize = NSSize(width: 22, height: 22)
    private static let networkSymbolRect = NSRect(x: 1, y: 3, width: 17, height: 17)
}
