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

    /// Human-readable status summary for the status bar.
    var statusSummary: String {
        guard hasDiscovered else {
            return String(localized: "gastown.status.discovering", defaultValue: "Gas Town: discovering…")
        }
        guard let townRoot else {
            return String(localized: "gastown.status.notConnected", defaultValue: "Gas Town: not connected")
        }
        let townName = ((townRoot.path as NSString).lastPathComponent)
        let rigCount = rigs.count
        return String(
            localized: "gastown.status.connected",
            defaultValue: "Gas Town: \(townName) (\(rigCount) rigs)"
        )
    }

    /// Whether a Gas Town workspace was detected.
    var isConnected: Bool { townRoot != nil }

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
                    #if DEBUG
                    dlog("GasTownService: detected \(discoveryResult.town.path) with \(discoveryResult.rigs.count) rigs")
                    #endif
                case .failure(let error):
                    self.townRoot = nil
                    self.rigs = []
                    self.gtCLIPath = nil
                    #if DEBUG
                    dlog("GasTownService: discovery failed — \(error)")
                    #endif
                }
                self.hasDiscovered = true
            }
        }
    }
}
