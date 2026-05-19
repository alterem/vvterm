//
//  KeychainStore.swift
//  VVTerm
//
//  Keychain wrapper for storing credentials with optional iCloud sync
//

import Foundation
import Security

enum AppKeychainIdentity {
    static let currentService = Bundle.main.bundleIdentifier ?? "app.agatha.VivyTerm"
    static let legacyServices = [
        "app.vivy.vvterm",
        "app.vivy.VivyTerm"
    ]
}

final class KeychainStore: @unchecked Sendable {
    private let service: String
    private let legacyServices: [String]

    nonisolated init(service: String, legacyServices: [String] = []) {
        self.service = service
        self.legacyServices = legacyServices.filter { $0 != service }
    }

#if os(macOS)
    private enum LocalKeychainBackend: CaseIterable {
        case dataProtection
        case standard

        static let preferredOrder: [LocalKeychainBackend] = [.dataProtection, .standard]
    }
#endif

    // MARK: - Data Operations

    nonisolated func set(_ data: Data, forKey key: String, iCloudSync: Bool = false) throws {
        if iCloudSync {
            try deleteExistingItem(forKey: key, service: service, iCloudSync: true)

            var attributes = baseQuery(forKey: key, service: service, iCloudSync: true)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            attributes[kSecAttrSynchronizable as String] = kCFBooleanTrue

            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unhandled(status)
            }
            return
        }

#if os(macOS)
        try deleteExistingLocalItems(forKey: key, service: service)

        var firstFailure: OSStatus?
        for backend in LocalKeychainBackend.preferredOrder {
            var attributes = baseQuery(forKey: key, service: service, iCloudSync: false, localBackend: backend)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecSuccess {
                return
            }
            if status == errSecMissingEntitlement {
                firstFailure = firstFailure ?? status
                continue
            }
            throw KeychainError.unhandled(status)
        }

        throw KeychainError.unhandled(firstFailure ?? errSecMissingEntitlement)
#else
        try deleteExistingItem(forKey: key, service: service, iCloudSync: false)

        var attributes = baseQuery(forKey: key, service: service, iCloudSync: false)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
#endif
    }

    nonisolated func get(_ key: String) throws -> Data? {
        if let data = try read(key, service: service, iCloudSync: false) {
            return data
        }

        for legacyService in legacyServices {
            if let legacyData = try read(key, service: legacyService, iCloudSync: false) {
                try? set(legacyData, forKey: key, iCloudSync: false)
                return legacyData
            }
        }

        return nil
    }

    nonisolated func delete(_ key: String) throws {
        try deleteExistingItem(forKey: key, service: service, iCloudSync: false)

        for legacyService in legacyServices {
            try deleteExistingItem(forKey: key, service: legacyService, iCloudSync: false)
        }
    }

    private nonisolated func read(_ key: String, service: String, iCloudSync: Bool) throws -> Data? {
        if iCloudSync {
            return try readSingleQuery(baseQuery(forKey: key, service: service, iCloudSync: true))
        }

#if os(macOS)
        var sawMissingEntitlement = false

        for backend in LocalKeychainBackend.preferredOrder {
            let query = baseQuery(forKey: key, service: service, iCloudSync: false, localBackend: backend)
            do {
                if let data = try readSingleQuery(query) {
                    return data
                }
            } catch KeychainError.unhandled(let status) where status == errSecMissingEntitlement {
                sawMissingEntitlement = true
                continue
            }
        }

        if sawMissingEntitlement {
            return nil
        }
        return nil
#else
        return try readSingleQuery(baseQuery(forKey: key, service: service, iCloudSync: false))
#endif
    }

    private nonisolated func baseQuery(
        forKey key: String,
        service: String,
        iCloudSync: Bool
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if iCloudSync {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }

        return query
    }

#if os(macOS)
    private nonisolated func baseQuery(
        forKey key: String,
        service: String,
        iCloudSync: Bool,
        localBackend: LocalKeychainBackend
    ) -> [String: Any] {
        var query = baseQuery(forKey: key, service: service, iCloudSync: iCloudSync)
        if !iCloudSync && localBackend == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        }
        return query
    }
#endif

    private nonisolated func readSingleQuery(_ query: [String: Any]) throws -> Data? {
        var query = query
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }

        return item as? Data
    }

    private nonisolated func deleteExistingItem(forKey key: String, service: String, iCloudSync: Bool) throws {
        if iCloudSync {
            var deleteQuery = baseQuery(forKey: key, service: service, iCloudSync: true)
            deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            try deleteSingleQuery(deleteQuery)
            return
        }

#if os(macOS)
        try deleteExistingLocalItems(forKey: key, service: service)
#else
        try deleteSingleQuery(baseQuery(forKey: key, service: service, iCloudSync: false))
#endif
    }

    private nonisolated func deleteSingleQuery(_ query: [String: Any]) throws {
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.unhandled(deleteStatus)
        }
    }

#if os(macOS)
    private nonisolated func deleteExistingLocalItems(forKey key: String, service: String) throws {
        var firstFailure: OSStatus?

        for backend in LocalKeychainBackend.preferredOrder {
            do {
                try deleteSingleQuery(baseQuery(forKey: key, service: service, iCloudSync: false, localBackend: backend))
            } catch KeychainError.unhandled(let status) where status == errSecMissingEntitlement {
                firstFailure = firstFailure ?? status
            }
        }

        if let firstFailure, firstFailure != errSecMissingEntitlement {
            throw KeychainError.unhandled(firstFailure)
        }
    }
#endif

    // MARK: - String Convenience

    nonisolated func setString(_ value: String, forKey key: String, iCloudSync: Bool = false) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try set(data, forKey: key, iCloudSync: iCloudSync)
    }

    nonisolated func getString(_ key: String) throws -> String? {
        guard let data = try get(key) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }
}

// MARK: - Keychain Error

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)
    case encodingFailed
    case decodingFailed
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            if status == errSecMissingEntitlement {
                return "Keychain error: \(status) (missing required code-signing entitlement)"
            }
            return "Keychain error: \(status)"
        case .encodingFailed:
            return "Failed to encode data for keychain"
        case .decodingFailed:
            return "Failed to decode data from keychain"
        case .itemNotFound:
            return "Item not found in keychain"
        }
    }
}
