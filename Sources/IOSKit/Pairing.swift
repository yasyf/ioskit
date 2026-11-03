// A Machine persists as JSON under Application Support; its bearer token, when it
// has one, lives in the Keychain keyed by machine id, never in the JSON file.

import Foundation
import Security

/// PairPayload is the handshake that pairs a daemon: the QR JSON
/// `{"v":1,"url":"http://host:port","token":"…"}`, or a tailnet link
/// `<scheme>://pair?url=…` whose token is absent because the phone's tailnet login
/// already authenticates it. Decoding rejects any version but 1 up front, so an
/// incompatible payload fails loudly at the boundary.
public struct PairPayload: Decodable, Equatable, Sendable {
    public let version: Int
    public let url: URL
    public let token: String?

    public init(version: Int, url: URL, token: String?) {
        self.version = version
        self.url = url
        self.token = token
    }

    public init(link: URL, scheme: String) throws {
        guard link.scheme == scheme, link.host() == "pair",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw), url.scheme == "http" || url.scheme == "https", url.host() != nil
        else { throw PairError.notAPairLink }
        self.init(version: 1, url: url, token: items.first { $0.name == "token" }?.value)
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case url
        case token
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode(Int.self, forKey: .version)
        guard decoded == 1 else { throw PairError.unsupportedVersion(decoded) }
        version = decoded
        url = try container.decode(URL.self, forKey: .url)
        token = try container.decodeIfPresent(String.self, forKey: .token)
    }
}

/// PairError is a rejected pairing payload.
public enum PairError: Error, Equatable {
    case unsupportedVersion(Int)
    case notAPairLink
}

/// Machine is a paired daemon the app remembers: a stable id (the Keychain account
/// for its token), a human name, and its base URL. The token is stored separately
/// in the Keychain, never in this record.
public struct Machine: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var baseURL: URL

    public init(id: String = UUID().uuidString, name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

/// MachineStore persists the paired-machine roster as JSON in an injected
/// directory. Production points it at Application Support via `defaultDirectory`;
/// tests point it at a temp directory so they never touch the real store.
public struct MachineStore: Sendable {
    private let fileURL: URL

    /// Creates a store whose `machines.json` lives in `directory`.
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("machines.json")
    }

    /// defaultDirectory is `Application Support/<namespace>`, created if absent.
    public static func defaultDirectory(namespace: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(namespace, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// load reads the roster, returning an empty list when nothing has been saved.
    public func load() throws -> [Machine] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Machine].self, from: data)
    }

    /// save writes the roster atomically, creating the directory if needed.
    public func save(_ machines: [Machine]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(machines)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// KeychainError wraps a non-success Security-framework OSStatus.
public struct KeychainError: Error, Equatable {
    public let status: OSStatus
    public init(status: OSStatus) {
        self.status = status
    }
}

/// TokenStore keeps a machine's bearer token in the Keychain as a generic-password
/// item under one service per app, keyed by the machine id. The calls are the
/// portable SecItem surface.
public struct TokenStore: Sendable {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    /// setToken writes (replacing any prior value) the token for `machineID`, bound to
    /// this device and readable by a background read after the first post-boot unlock.
    public func setToken(_ token: String, machineID: String) throws {
        let changes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery(machineID) as CFDictionary, changes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }
        var attributes = baseQuery(machineID)
        attributes.merge(changes) { _, new in new }
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        // A concurrent writer created the item between our update miss and this add;
        // fold our value in with a final update rather than throwing a spurious dup.
        guard addStatus == errSecDuplicateItem else { throw KeychainError(status: addStatus) }
        let retryStatus = SecItemUpdate(baseQuery(machineID) as CFDictionary, changes as CFDictionary)
        guard retryStatus == errSecSuccess else { throw KeychainError(status: retryStatus) }
    }

    /// token reads the token for `machineID`, or nil when the machine has none: a
    /// tailnet pairing, or a machine that must be paired again.
    public func token(machineID: String) throws -> String? {
        var query = baseQuery(machineID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else {
            throw KeychainError(status: errSecInternalError)
        }
        guard let token = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return token
    }

    /// deleteToken removes the token for `machineID`; a missing item is not an error.
    public func deleteToken(machineID: String) throws {
        let status = SecItemDelete(baseQuery(machineID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(_ machineID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: machineID,
        ]
    }
}
