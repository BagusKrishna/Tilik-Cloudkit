//
//  CollaborationCloudServing.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

public struct CollaborationDelta {
    public var workspaces: [TPAWorkspace] = []
    public var events: [String: [CollaborationEvent]] = [:]
    public var deletions: [String: Set<String>] = [:]
    public var removedWorkspaces: Set<String> = []
    public var resetZones: Set<String> = []
    public var databaseTokens: [String: Data] = [:]
    public var zoneTokens: [String: Data] = [:]

    public init() {}
}

public struct CollaborationInvitation: Identifiable, Equatable {
    public let workspaceID: String
    public let participantID: String
    public let url: URL
    public var id: String { participantID }

    public init(workspaceID: String, participantID: String, url: URL) {
        self.workspaceID = workspaceID
        self.participantID = participantID
        self.url = url
    }
}

public enum CollaborationInvitationCancellation: Equatable {
    case cancelled
    case accepted
    case missing
}

/// CloudKit details stay behind an injectable boundary.
@MainActor
public protocol CollaborationCloudServing {
    var containerIdentifier: String { get }
    func accountID() async throws -> String
    func changes(since snapshot: CollaborationSnapshot) async throws -> CollaborationDelta
    func createWorkspace(name: String, accountID: String) async throws -> TPAWorkspace
    func renameWorkspace(_ workspace: TPAWorkspace, name: String) async throws -> TPAWorkspace
    func deleteWorkspace(_ workspace: TPAWorkspace) async throws
    func save(_ mutation: PendingMutation) async throws -> CollaborationEvent
    func reconcile(_ mutation: PendingMutation) async throws -> CollaborationEvent?
    func invitation(for workspace: TPAWorkspace) async throws -> CollaborationInvitation
    func cancelInvitation(_ invitation: CollaborationInvitation, workspace: TPAWorkspace) async throws
        -> CollaborationInvitationCancellation
    /// Includes the owner and accepted participants; identity is available only when CloudKit provides it.
    func members(of workspace: TPAWorkspace) async throws -> [CollaborationMember]?
    func officerEmail(in workspace: TPAWorkspace) async throws -> String?
    func officerParticipantID(in workspace: TPAWorkspace) async throws -> String?
    func saveOfficerProfile(name: String, email: String?, in workspace: TPAWorkspace) async throws
    func revoke(memberID: String?, workspace: TPAWorkspace) async throws
    func join(url: URL, accountID: String) async throws
    func leave(_ workspace: TPAWorkspace, accountID: String) async throws
    func resetEvents(in workspace: TPAWorkspace) async throws
    func registerSubscriptions() async throws
    func retryDate(for error: Error) -> Date?
    func isAccessError(_ error: Error) -> Bool
    func message(for error: Error) -> String
}

public extension CollaborationCloudServing {
    func officerEmail(in workspace: TPAWorkspace) async throws -> String? { nil }
    func officerParticipantID(in workspace: TPAWorkspace) async throws -> String? { nil }
    func saveOfficerProfile(name: String, email: String?, in workspace: TPAWorkspace) async throws {
        throw CollaborationError.accountUnavailable
    }
    func message(for error: Error) -> String {
        "Pembaruan iCloud belum selesai. Data tersimpan tetap tersedia; periksa koneksi dan coba lagi."
    }
}
