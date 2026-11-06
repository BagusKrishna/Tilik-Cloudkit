//
//  CollaborationLocalStore.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation
import CryptoKit

/// Persists cache, outbox, tokens, and alert ledger together.
@MainActor
public protocol CollaborationPersisting {
    func load(accountID: String) throws -> CollaborationSnapshot
    func save(_ snapshot: CollaborationSnapshot) throws
}

/// A corrupt store is an error; it must never be replaced with an empty snapshot.
@MainActor
public final class CollaborationLocalStore: CollaborationPersisting {
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func load(accountID: String) throws -> CollaborationSnapshot {
        let url = fileURL(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CollaborationSnapshot(accountID: accountID)
        }
        let value = try JSONDecoder().decode(CollaborationSnapshot.self, from: Data(contentsOf: url))
        guard value.accountID == accountID else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    public func save(_ snapshot: CollaborationSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
            try data.write(to: fileURL(snapshot.accountID), options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
            try data.write(to: fileURL(snapshot.accountID), options: .atomic)
        #endif
    }

    private func fileURL(_ accountID: String) -> URL {
        let hash = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
