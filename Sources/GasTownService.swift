import Foundation
import Combine
#if DEBUG
import Bonsplit
#endif

/// Singleton service that runs Gas Town discovery on app launch and exposes
/// the discovered town root, rigs, and gt CLI path as observable state.
///
/// SwiftUI views and menu items observe this to enable/disable Gas Town features.
@MainActor
final class GasTownService: ObservableObject {
    static let shared = GasTownService()

    /// The discovered town root, or nil if not found.
    @Published private(set) var townRoot: TownRoot?

    /// Discovered rigs in the town.
    @Published private(set) var rigs: [RigInfo] = []

    /// Path to the gt CLI binary, or nil if not on PATH.
    @Published private(set) var gtCLIPath: String?

    /// Whether discovery has completed (regardless of success/failure).
    @Published private(set) var hasDiscovered: Bool = false

    /// Incremented on each refresh tick — panels observe this to auto-refresh.
    @Published private(set) var refreshTick: Int = 0

    /// Interval between auto-refresh ticks (seconds).
    let refreshInterval: TimeInterval = 8.0

    /// Human-readable status summary for the status bar.
    var statusSummary: String {
        guard hasDiscovered else {
            return String(localized: "gastown.status.discovering", defaultValue: "Gas Town: discovering...")
        }
        guard let townRoot else {
            return String(localized: "gastown.status.notConnected", defaultValue: "Gas Town: not connected")
        }
        let townName = ((townRoot.path as NSString).lastPathComponent)
        let rigCount = rigs.count
        let format = String(
            localized: "gastown.status.connected.format",
            defaultValue: "Gas Town: %@ (%d rigs)"
        )
        return String(format: format, townName, rigCount)
    }

    /// Whether a Gas Town workspace was detected.
    var isConnected: Bool { townRoot != nil }

    var rigOverviewTitle: String {
        String(localized: "gastown.rigOverview.title", defaultValue: "Gas Town Rig Overview")
    }

    var rigOverviewOKButtonTitle: String {
        String(localized: "gastown.rigOverview.ok", defaultValue: "OK")
    }

    var rigOverviewInformativeText: String {
        var lines: [String] = []

        if let townRoot {
            let format = String(
                localized: "gastown.rigOverview.town.format",
                defaultValue: "Town: %@"
            )
            lines.append(String(format: format, townRoot.path))
        } else {
            lines.append(String(
                localized: "gastown.rigOverview.town.notConnected",
                defaultValue: "Town: not connected"
            ))
        }

        let rigsFormat = String(
            localized: "gastown.rigOverview.rigs.format",
            defaultValue: "Rigs (%d):"
        )
        lines.append(String(format: rigsFormat, rigs.count))

        if rigs.isEmpty {
            lines.append(String(
                localized: "gastown.rigOverview.rigs.empty",
                defaultValue: "  - No rigs discovered"
            ))
        } else {
            for rig in rigs {
                if let prefix = rig.beadsPrefix {
                    let format = String(
                        localized: "gastown.rigOverview.rigWithPrefix.format",
                        defaultValue: "  - %@ [%@]"
                    )
                    lines.append(String(format: format, rig.name, prefix))
                } else {
                    let format = String(
                        localized: "gastown.rigOverview.rig.format",
                        defaultValue: "  - %@"
                    )
                    lines.append(String(format: format, rig.name))
                }
            }
        }

        if let gtCLIPath {
            let format = String(
                localized: "gastown.rigOverview.gtCLI.format",
                defaultValue: "gt CLI: %@"
            )
            lines.append("")
            lines.append(String(format: format, gtCLIPath))
        }

        return lines.joined(separator: "\n")
    }

    private var refreshTimer: Timer?

    private init() {}

    /// Run discovery on a background thread and publish results on main.
    func discover() {
        let discovery = GasTownDiscovery()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = discovery.discover()
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let discoveryResult):
                    self.townRoot = discoveryResult.town
                    self.rigs = discoveryResult.rigs
                    self.gtCLIPath = discoveryResult.gtCLIPath
                    self.startRefreshTimer()
                    // Start the centralized Dolt socket adapter for
                    // direct-query data fetching (replaces CLI subprocesses).
                    GasTownSocketAdapter.shared.configureDatabases(
                        ["hq"] + discoveryResult.rigs.map(\.id)
                    )
                    GasTownSocketAdapter.shared.startWatching()
                    #if DEBUG
                    dlog("GasTownService: detected \(discoveryResult.town.path) with \(discoveryResult.rigs.count) rigs")
                    #endif
                case .failure(let error):
                    self.townRoot = nil
                    self.rigs = []
                    self.gtCLIPath = nil
                    self.stopRefreshTimer()
                    GasTownSocketAdapter.shared.stopWatching()
                    #if DEBUG
                    dlog("GasTownService: discovery failed — \(error)")
                    #endif
                }
                self.hasDiscovered = true
            }
        }
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshTick += 1
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
