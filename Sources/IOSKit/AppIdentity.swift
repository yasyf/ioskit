import Foundation

public struct AppIdentity: Sendable, Equatable {
    public let name: String
    public let storageNamespace: String
    public let bonjourType: String
    public let pairScheme: String

    public init(name: String, storageNamespace: String, bonjourType: String, pairScheme: String) {
        self.name = name
        self.storageNamespace = storageNamespace
        self.bonjourType = bonjourType
        self.pairScheme = pairScheme
    }

    public var keychainService: String {
        "\(storageNamespace).v1"
    }
}
