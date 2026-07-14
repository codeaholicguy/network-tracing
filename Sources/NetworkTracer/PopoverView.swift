import AppKit
import SwiftUI
import NetworkTracerCore

struct PopoverView: View {
    @EnvironmentObject var store: ConnectionStore
    @State private var showingAcceptedPatterns = false
    @State private var alertMessage: String?
    @State private var copiedHostPortRecordID: ConnectionRecord.ID?
    @State private var copyFeedbackToken = UUID()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Fixed column widths (Host:Port is flexible — takes remaining space)
    private let markerWidth: CGFloat = 24
    private let appWidth:  CGFloat = 120
    private let orgWidth:  CGFloat = 96
    private let timeWidth: CGFloat = 66
    private let actionWidth: CGFloat = 86
    private let copyFeedbackDuration: TimeInterval = 1.5

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnHeaders
            Divider()
            connectionList
        }
        .frame(width: 640, height: 340)
        .sheet(isPresented: $showingAcceptedPatterns) {
            AcceptedPatternsView(alertMessage: $alertMessage)
                .environmentObject(store)
        }
        .alert("NetworkTracer", isPresented: alertIsPresented) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Network Connections")
                .font(.headline)
            Spacer()
            if store.attentionCount > 0 {
                Text("\(store.attentionCount) need attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Approve All") {
                    approveAll()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .font(.caption)
                .help("Approve All Endpoints Needing Attention")
            }
            Text("\(store.connections.count) active")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Needs Attention", isOn: $store.needsAttentionOnly)
                .toggleStyle(.checkbox)
                .font(.caption)
            Button {
                showingAcceptedPatterns = true
            } label: {
                Image(systemName: "checkmark.shield")
            }
            .buttonStyle(.borderless)
            .help("Accepted Patterns")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: markerWidth, alignment: .leading)
            Text("App")
                .frame(width: appWidth, alignment: .leading)
            Text("Host : Port")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Org")
                .frame(width: orgWidth, alignment: .leading)
            Text("Last Seen")
                .frame(width: timeWidth, alignment: .trailing)
            Text("Action")
                .frame(width: actionWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var connectionList: some View {
        if store.visibleConnections.isEmpty {
            Spacer()
            Text(store.needsAttentionOnly ? "No connections need attention" : "No active connections")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(store.visibleConnections) { record in
                connectionRow(record)
            }
            .listStyle(.plain)
        }
    }

    private func connectionRow(_ record: ConnectionRecord) -> some View {
        HStack(spacing: 0) {
            attentionMarker(for: record)
                .frame(width: markerWidth, alignment: .leading)

            Text(record.processName)
                .frame(width: appWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                HostPortCopyButton(record.copyableHostPort) {
                    copyHostPort(record)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Copy \(record.copyableHostPort)")

                if copiedHostPortRecordID == record.id {
                    Text("Copied")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.org ?? "—")
                .frame(width: orgWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(record.org == nil ? .secondary : .primary)

            Text(Self.timeFormatter.string(from: record.lastSeen))
                .frame(width: timeWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            approvalControl(for: record)
                .frame(width: actionWidth, alignment: .trailing)
        }
        .font(.system(.body, design: .monospaced))
    }

    @ViewBuilder
    private func attentionMarker(for record: ConnectionRecord) -> some View {
        if record.attention.state == .needsAttention {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .help(record.attention.message)
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .help("Accepted")
        }
    }

    @ViewBuilder
    private func approvalControl(for record: ConnectionRecord) -> some View {
        if record.attention.state == .needsAttention {
            Button {
                acceptEndpoint(record)
            } label: {
                Text("Approve")
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .font(.caption)
            .help("Approve Endpoint")
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .help("Accepted")
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    private func acceptEndpoint(_ record: ConnectionRecord) {
        do {
            try store.acceptEndpoint(forID: record.id)
        } catch {
            alertMessage = "Could not accept endpoint: \(error.localizedDescription)"
        }
    }

    private func copyHostPort(_ record: ConnectionRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.copyableHostPort, forType: .string)

        let token = UUID()
        copyFeedbackToken = token
        copiedHostPortRecordID = record.id

        DispatchQueue.main.asyncAfter(deadline: .now() + copyFeedbackDuration) {
            guard copyFeedbackToken == token else { return }
            copiedHostPortRecordID = nil
        }
    }

    private func approveAll() {
        do {
            let acceptedCount = try store.acceptAllNeedingAttention()
            if acceptedCount > 0 {
                alertMessage = "Approved \(acceptedCount) endpoint\(acceptedCount == 1 ? "" : "s")."
            }
        } catch {
            alertMessage = "Could not approve all endpoints: \(error.localizedDescription)"
        }
    }
}

private struct HostPortCopyButton: NSViewRepresentable {
    let text: String
    let onClick: () -> Void

    init(_ text: String, onClick: @escaping () -> Void) {
        self.text = text
        self.onClick = onClick
    }

    func makeNSView(context: Context) -> HostPortButton {
        let button = HostPortButton(title: text, target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.alignment = .left
        button.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.lineBreakMode = .byTruncatingMiddle
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.toolTip = text
        return button
    }

    func updateNSView(_ button: HostPortButton, context: Context) {
        button.title = text
        button.toolTip = text
        context.coordinator.onClick = onClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClick: onClick)
    }

    final class Coordinator: NSObject {
        var onClick: () -> Void

        init(onClick: @escaping () -> Void) {
            self.onClick = onClick
        }

        @objc func handleClick(_ sender: NSButton) {
            onClick()
        }
    }
}

private final class HostPortButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
