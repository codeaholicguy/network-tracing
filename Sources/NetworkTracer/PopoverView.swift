import SwiftUI
import NetworkTracerCore

struct PopoverView: View {
    @EnvironmentObject var store: ConnectionStore

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Fixed column widths (Host:Port is flexible — takes remaining space)
    private let appWidth:  CGFloat = 130
    private let orgWidth:  CGFloat = 100
    private let timeWidth: CGFloat = 70

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnHeaders
            Divider()
            connectionList
        }
        .frame(width: 580, height: 340)
    }

    private var header: some View {
        HStack {
            Text("Network Connections")
                .font(.headline)
            Spacer()
            Text("\(store.connections.count) active")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("App")
                .frame(width: appWidth, alignment: .leading)
            Text("Host : Port")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Org")
                .frame(width: orgWidth, alignment: .leading)
            Text("Last Seen")
                .frame(width: timeWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var connectionList: some View {
        if store.connections.isEmpty {
            Spacer()
            Text("No active connections")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(store.connections) { record in
                connectionRow(record)
            }
            .listStyle(.plain)
        }
    }

    private func connectionRow(_ record: ConnectionRecord) -> some View {
        HStack(spacing: 0) {
            Text(record.processName)
                .frame(width: appWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(record.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(record.org ?? "—")
                .frame(width: orgWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(record.org == nil ? .secondary : .primary)

            Text(Self.timeFormatter.string(from: record.lastSeen))
                .frame(width: timeWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(.body, design: .monospaced))
    }
}
