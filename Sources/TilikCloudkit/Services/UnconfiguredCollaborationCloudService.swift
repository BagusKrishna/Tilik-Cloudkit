//
//  UnconfiguredCollaborationCloudService.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Missing configuration is explicit and never falls back to another developer's cloud.
@MainActor
public final class UnconfiguredCollaborationCloudService: CollaborationCloudServing {
    public let containerIdentifier = ""

    public init() {}
    public func accountID() async throws -> String { throw CollaborationError.configurationMissing }
    public func changes(since snapshot: CollaborationSnapshot) async throws -> CollaborationDelta {
        throw CollaborationError.configurationMissing
    }
    public func createWorkspace(name: String, accountID: String) async throws -> TPAWorkspace {
        throw CollaborationError.configurationMissing
    }
    public func renameWorkspace(_ workspace: TPAWorkspace, name: String) async throws -> TPAWorkspace {
        throw CollaborationError.configurationMissing
    }
    public func deleteWorkspace(_ workspace: TPAWorkspace) async throws {
        throw CollaborationError.configurationMissing
    }
    public func save(_ mutation: PendingMutation) async throws -> CollaborationEvent {
        throw CollaborationError.configurationMissing
    }
    public func reconcile(_ mutation: PendingMutation) async throws -> CollaborationEvent? {
        throw CollaborationError.configurationMissing
    }
    public func invitation(for workspace: TPAWorkspace) async throws -> CollaborationInvitation {
        throw CollaborationError.configurationMissing
    }
    public func cancelInvitation(_ invitation: CollaborationInvitation, workspace: TPAWorkspace) async throws -> CollaborationInvitationCancellation {
        throw CollaborationError.configurationMissing
    }
    public func members(of workspace: TPAWorkspace) async throws -> [CollaborationMember]? {
        throw CollaborationError.configurationMissing
    }
    public func revoke(memberID: String?, workspace: TPAWorkspace) async throws {
        throw CollaborationError.configurationMissing
    }
    public func join(url: URL, accountID: String) async throws {
        throw CollaborationError.configurationMissing
    }
    public func leave(_ workspace: TPAWorkspace, accountID: String) async throws {
        throw CollaborationError.configurationMissing
    }
    public func resetEvents(in workspace: TPAWorkspace) async throws {
        throw CollaborationError.configurationMissing
    }
    public func registerSubscriptions() async throws { throw CollaborationError.configurationMissing }
    public func retryDate(for error: Error) -> Date? { nil }
    public func isAccessError(_ error: Error) -> Bool { false }
}
