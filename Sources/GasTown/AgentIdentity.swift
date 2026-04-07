import Foundation

/// A canonical reference to a Gas Town agent.
///
/// Agent addresses follow the pattern `<rig>/<role>[/<name>]`:
/// - Singular roles (mayor, refinery, witness): `gmux/mayor`
/// - Multi-member roles (crew, polecats): `gmux/crew/architect`
struct AgentIdentity: Equatable, Hashable {
    /// The rig this agent belongs to (e.g. `"gmux"`).
    let rig: String

    /// The role of this agent within the rig.
    let role: RigRole

    /// The member name within the role directory.
    ///
    /// `nil` for singular roles (mayor, refinery, witness).
    /// Required for multi-member roles (crew, polecats).
    let name: String?

    /// The canonical address string (e.g. `"gmux/polecats/chrome"`).
    var address: String {
        if let name {
            return "\(rig)/\(role.rawValue)/\(name)"
        }
        return "\(rig)/\(role.rawValue)"
    }
}

// MARK: - Parsing

extension AgentIdentity {
    /// Errors from parsing agent address strings.
    enum ParseError: Equatable, Error {
        /// The address is empty.
        case empty

        /// The address has fewer than 2 components (need at least `rig/role`).
        case tooFewComponents(String)

        /// The role component is not a recognized ``RigRole``.
        case unknownRole(String)

        /// A singular role was given a name component.
        case nameOnSingularRole(role: RigRole, name: String)
    }

    /// Parse a slash-separated agent address string.
    ///
    /// - Parameter address: A string like `"gmux/polecats/chrome"` or `"gmux/mayor"`.
    /// - Returns: A validated ``AgentIdentity``.
    /// - Throws: ``ParseError`` if the address is malformed.
    static func parse(_ address: String) throws -> AgentIdentity {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ParseError.empty
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2 else {
            throw ParseError.tooFewComponents(trimmed)
        }

        let rigName = components[0]
        guard let role = RigRole(rawValue: components[1]) else {
            throw ParseError.unknownRole(components[1])
        }

        let name = components.count > 2 ? components[2] : nil

        if role.isSingular, let name {
            throw ParseError.nameOnSingularRole(role: role, name: name)
        }

        return AgentIdentity(rig: rigName, role: role, name: name)
    }
}
