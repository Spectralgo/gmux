import Foundation

/// A structured Gas Town agent address.
///
/// Agent addresses follow the form `<rig>/<role>/<name>` for multi-member
/// roles (crew, polecats) or `<rig>/<role>` for singular roles (mayor,
/// refinery, witness). Examples:
///
///     gmux/polecats/chrome
///     spectralChat/crew/joe
///     gmux/refinery
///     gmux/mayor
///
/// This type is the canonical way to reference a Gas Town agent across
/// UI, CLI, socket, and notification surfaces.
struct AgentIdentity: Equatable, Hashable {
    /// The rig this agent belongs to (e.g. `"gmux"`).
    let rig: String

    /// The role within the rig (e.g. `.polecats`, `.crew`).
    let role: RigRole

    /// The member name within a multi-member role.
    ///
    /// Non-nil for crew and polecats (e.g. `"chrome"`, `"joe"`).
    /// Nil for singular roles (mayor, refinery, witness).
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

    /// Parsing failures for agent address strings.
    enum ParseError: Equatable, Error {
        /// The address string has fewer than two path components.
        case tooFewComponents(String)

        /// The role component does not match any known ``RigRole``.
        case unknownRole(String)

        /// A multi-member role was given without a member name.
        case missingMemberName(role: String)

        /// A singular role was given with an unexpected member name.
        case unexpectedMemberName(role: String, name: String)
    }

    /// Parse an agent address string into a structured identity.
    ///
    /// - Parameter address: A slash-separated address such as `"gmux/polecats/chrome"`.
    /// - Returns: A validated ``AgentIdentity``.
    /// - Throws: ``ParseError`` if the address is malformed.
    static func parse(_ address: String) throws -> AgentIdentity {
        let components = address.split(separator: "/").map(String.init)

        guard components.count >= 2 else {
            throw ParseError.tooFewComponents(address)
        }

        let rigName = components[0]
        let roleString = components[1]

        guard let role = RigRole(rawValue: roleString) else {
            throw ParseError.unknownRole(roleString)
        }

        let memberName = components.count >= 3 ? components[2] : nil

        if role.isSingular {
            if let name = memberName {
                throw ParseError.unexpectedMemberName(role: roleString, name: name)
            }
            return AgentIdentity(rig: rigName, role: role, name: nil)
        }

        // Multi-member role requires a name.
        guard let name = memberName else {
            throw ParseError.missingMemberName(role: roleString)
        }

        return AgentIdentity(rig: rigName, role: role, name: name)
    }
}
