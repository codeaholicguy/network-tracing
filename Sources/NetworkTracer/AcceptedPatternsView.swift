import AppKit
import SwiftUI
import NetworkTracerCore

struct AcceptedPatternsView: View {
    @EnvironmentObject var store: ConnectionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var alertMessage: String?

    private var patterns: [(id: String, pattern: AcceptedHighlightPattern)] {
        store.acceptedPatterns
            .map { (id: $0.key, pattern: $0.value) }
            .sorted {
                if $0.pattern.processName == $1.pattern.processName {
                    return $0.pattern.value < $1.pattern.value
                }
                return $0.pattern.processName < $1.pattern.processName
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(width: 560, height: 360)
    }

    private var toolbar: some View {
        HStack {
            Text("Accepted Patterns")
                .font(.headline)
            Spacer()
            Button("Import") { importPatterns() }
            Button("Export") { exportPatterns() }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if patterns.isEmpty {
            Spacer()
            Text("No accepted patterns")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List {
                ForEach(patterns, id: \.id) { item in
                    acceptedPatternRow(id: item.id, pattern: item.pattern)
                }
            }
            .listStyle(.plain)
        }
    }

    private func acceptedPatternRow(id: String, pattern: AcceptedHighlightPattern) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.processName)
                    .font(.headline)
                    .lineLimit(1)
                Text(pattern.value)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                metadata(id: id, org: pattern.org)
            }
            Spacer()
            Button {
                remove(id: id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove Accepted Pattern")
        }
        .padding(.vertical, 4)
    }

    private func metadata(id: String, org: String?) -> some View {
        HStack(spacing: 8) {
            Text(id)
                .lineLimit(1)
                .truncationMode(.middle)
            if let org {
                Text(org)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func remove(id: String) {
        do {
            try store.removeAcceptedPattern(id: id)
        } catch {
            alertMessage = "Could not remove accepted pattern: \(error.localizedDescription)"
        }
    }

    private func importPatterns() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let summary = try store.importAcceptedPatterns(from: url)
            alertMessage = "Import complete: \(summary.added) added, \(summary.duplicates) duplicates, \(summary.rejected) rejected, \(summary.filledMissingOrg) org filled."
        } catch {
            alertMessage = "Could not import accepted patterns: \(error.localizedDescription)"
        }
    }

    private func exportPatterns() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "accepted-patterns.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportAcceptedPatterns(to: url)
            alertMessage = "Accepted patterns exported."
        } catch {
            alertMessage = "Could not export accepted patterns: \(error.localizedDescription)"
        }
    }
}
