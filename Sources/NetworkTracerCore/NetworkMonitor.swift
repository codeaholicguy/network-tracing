import Foundation

/// Polls a data source on a fixed interval and pushes parsed addresses into `ConnectionStore`.
/// The data source defaults to `/usr/sbin/lsof`; an injectable closure enables unit testing.
public actor NetworkMonitor {
    public static let shared = NetworkMonitor()

    private var monitorTask: Task<Void, Never>?
    let pollInterval: TimeInterval          // internal for testability
    private let dataProvider: () -> String  // injectable for testability

    /// Production singleton — uses real lsof.
    public init() {
        self.pollInterval = 5.0
        self.dataProvider = { NetworkMonitor.runLSOF() }
    }

    /// Testable init — inject canned output and a short interval.
    init(pollInterval: TimeInterval, dataProvider: @escaping () -> String) {
        self.pollInterval = pollInterval
        self.dataProvider = dataProvider
    }

    /// Begin polling. Safe to call multiple times — cancels any prior poll loop.
    public func start(store: ConnectionStore) {
        monitorTask?.cancel()
        monitorTask = Task {
            while !Task.isCancelled {
                let output = dataProvider()
                let addresses = ConnectionParser.parse(output)
                await store.update(with: addresses)
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Runs `/usr/sbin/lsof -i -n -P` and returns stdout.
    /// Returns "" on any failure so callers treat it as an empty result.
    private static func runLSOF() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -i    : network files only
        // -n    : no hostname resolution (handled by DNSResolver)
        // -P    : no port-name resolution (show numeric ports)
        // +c 0  : unlimited COMMAND column width (full process name, not truncated)
        process.arguments = ["-i", "-n", "-P", "+c", "0"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        do {
            try process.run()
            // FIXME: waitUntilExit() blocks the caller's thread. Safe for v1 (lsof
            // completes in <500ms) but should be replaced with async Process completion
            // if this actor ever shares a thread pool with latency-sensitive work.
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
