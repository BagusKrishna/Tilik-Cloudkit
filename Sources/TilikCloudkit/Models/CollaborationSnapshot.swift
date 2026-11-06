//
//  CollaborationSnapshot.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Cache and checkpoints are committed in one atomic local transaction.
public struct CollaborationSnapshot: Codable, Equatable, Sendable {
    public enum AlertDisposition: String, Codable, Sendable { case scheduled, suppressed, failed }

    public let accountID: String
    public var workspaces: [TPAWorkspace] = []
    public var events: [String: [CollaborationEvent]] = [:]
    public var pending: [PendingMutation] = []
    public var databaseTokens: [String: Data] = [:]
    public var zoneTokens: [String: Data] = [:]
    public var alertLedger: [String: AlertDisposition] = [:]
    public var bootstrappedWorkspaces: Set<String> = []
    public var resetInProgress: Set<String> = []
    public var unavailableWorkspaceKeys: Set<String>?
    public var dismissedUnavailableWorkspaceKeys: Set<String>?
    public var deletingWorkspaceKeys: Set<String>?
    public var activeWorkspaceKeys: [String: String]?

    public init(accountID: String) { self.accountID = accountID }

    public mutating func removeWorkspace(_ key: String) {
        if unavailableWorkspaceKeys == nil { unavailableWorkspaceKeys = [] }
        unavailableWorkspaceKeys?.insert(key)
        workspaces.removeAll { $0.id == key }
        events.removeValue(forKey: key)
        activeWorkspaceKeys = activeWorkspaceKeys?.filter { $0.value != key }
        resetInProgress.remove(key)
        zoneTokens.removeValue(forKey: key)
        bootstrappedWorkspaces.remove(key)
        for index in pending.indices where pending[index].context.key == key {
            pending[index].state = .failed
            pending[index].retryAt = nil
            pending[index].errorMessage = "Akses TPA tidak tersedia. Kiriman dihentikan."
        }
    }
}
