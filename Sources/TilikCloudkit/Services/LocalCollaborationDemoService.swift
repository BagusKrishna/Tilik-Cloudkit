//
//  LocalCollaborationDemoService.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Single-device demo. Stores real local inputs; never contacts or impersonates CloudKit.
@MainActor
public final class LocalCollaborationDemoService: CollaborationCloudServing {
    public let containerIdentifier = "tilik-local-demo"
    private let file: URL
    private let account = "local-demo-account"

    private struct State: Codable {
        var workspaces: [TPAWorkspace] = []
        var events: [String: [CollaborationEvent]] = [:]
    }

    public init(directory: URL) { file = directory.appendingPathComponent("demo-data-v1.json") }

    public func accountID() async throws -> String { account }

    /// Prepare a participant projection for the explicit single-device demo entry.
    /// Existing local input survives repeated entry and app relaunches.
    public func prepareOfficerWorkspace() throws {
        var state = try load()
        guard state.workspaces.isEmpty else { return }
        state.workspaces.append(TPAWorkspace(
            context: context(UUID().uuidString, scope: .owner),
            name: "TPA Contoh · Mode Demo", ownerAccountID: account, schemaVersion: 1
        ))
        try persist(state)
    }

    public func changes(since snapshot: CollaborationSnapshot) async throws -> CollaborationDelta {
        let state = try load()
        var delta = CollaborationDelta()
        let owners = state.workspaces
        // The participant projection is a local simulation, not a CKShare membership.
        let participant = owners.first.map { workspace in
            TPAWorkspace(
                context: context(workspace.context.workspaceID, scope: .participant), name: workspace.name,
                ownerAccountID: account, schemaVersion: 1)
        }
        delta.workspaces = owners + (participant.map { [$0] } ?? [])
        let available = Set(delta.workspaces.map(\.id))
        delta.removedWorkspaces = Set(snapshot.workspaces.map(\.id)).subtracting(available)
        for workspace in delta.workspaces {
            delta.resetZones.insert(workspace.id)
            delta.events[workspace.id] = state.events[workspace.context.workspaceID] ?? []
        }
        return delta
    }

    public func createWorkspace(name: String, accountID: String) async throws -> TPAWorkspace {
        guard accountID == account, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CollaborationError.notOwner
        }
        var state = try load()
        guard state.workspaces.isEmpty else { throw CollaborationError.workspaceExists }
        let workspace = TPAWorkspace(
            context: context(UUID().uuidString, scope: .owner), name: name,
            ownerAccountID: account, schemaVersion: 1)
        state.workspaces.append(workspace)
        try persist(state)
        return workspace
    }

    public func renameWorkspace(_ workspace: TPAWorkspace, name: String) async throws -> TPAWorkspace {
        var state = try load()
        try validate(workspace.context, in: state)
        guard workspace.context.scope == .owner else { throw CollaborationError.notOwner }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CollaborationError.invalidName }
        let renamed = TPAWorkspace(
            context: workspace.context, name: trimmed, ownerAccountID: account, schemaVersion: 1)
        state.workspaces.removeAll { $0.id == workspace.id }
        state.workspaces.append(renamed)
        try persist(state)
        return renamed
    }

    public func deleteWorkspace(_ workspace: TPAWorkspace) async throws {
        var state = try load()
        guard workspace.context.scope == .owner, workspace.context.container == containerIdentifier,
            workspace.context.zoneOwner == account, workspace.ownerAccountID == account
        else { throw CollaborationError.notOwner }
        state.workspaces.removeAll { $0.id == workspace.id }
        state.events.removeValue(forKey: workspace.context.workspaceID)
        try persist(state)
    }

    public func save(_ mutation: PendingMutation) async throws -> CollaborationEvent {
        var state = try load()
        try validate(mutation.context, in: state)
        if let existing = state.events[mutation.event.workspaceID]?.first(where: {
            $0.id == mutation.id
        }) {
            guard existing.representsSameIntent(as: mutation.event) else {
                throw CollaborationError.conflictingEvent
            }
            return existing
        }
        if let target = mutation.event.hotspotID {
            guard
                state.events[mutation.event.workspaceID, default: []].contains(where: {
                    $0.kind == .hotspot && $0.id == target
                })
            else { throw CollaborationError.targetUnavailable }
        }
        var accepted = mutation.event
        accepted.serverCreatedAt = Date()  // Adapter acknowledgement only; the UI explicitly labels this local data.
        state.events[accepted.workspaceID, default: []].append(accepted)
        try persist(state)
        return accepted
    }

    public func reconcile(_ mutation: PendingMutation) async throws -> CollaborationEvent? {
        let state = try load()
        try validate(mutation.context, in: state)
        guard
            let event = state.events[mutation.event.workspaceID]?.first(where: { $0.id == mutation.id })
        else {
            return nil
        }
        guard event.representsSameIntent(as: mutation.event) else {
            throw CollaborationError.conflictingEvent
        }
        return event
    }

    public func resetEvents(in workspace: TPAWorkspace) async throws {
        var state = try load()
        try validate(workspace.context, in: state)
        guard workspace.context.scope == .owner else { throw CollaborationError.notOwner }
        state.events[workspace.context.workspaceID] = []
        try persist(state)
    }

    public func members(of workspace: TPAWorkspace) async throws -> [CollaborationMember]? { nil }
    public func invitation(for workspace: TPAWorkspace) async throws -> CollaborationInvitation {
        throw CollaborationError.configurationMissing
    }
    public func cancelInvitation(_ invitation: CollaborationInvitation, workspace: TPAWorkspace) async throws -> CollaborationInvitationCancellation { .missing }
    public func revoke(memberID: String?, workspace: TPAWorkspace) async throws {
        throw CollaborationError.configurationMissing
    }
    public func join(url: URL, accountID: String) async throws {
        throw CollaborationError.configurationMissing
    }
    public func leave(_ workspace: TPAWorkspace, accountID: String) async throws {
        throw CollaborationError.configurationMissing
    }
    public func registerSubscriptions() async throws {}
    public func retryDate(for error: Error) -> Date? { nil }
    public func isAccessError(_ error: Error) -> Bool { false }
    public func message(for error: Error) -> String {
        "Data demo lokal belum tersimpan. Periksa ruang penyimpanan dan coba lagi."
    }

    private func context(_ id: String, scope: WorkspaceContext.Scope) -> WorkspaceContext {
        WorkspaceContext(
            container: containerIdentifier, scope: scope, zoneName: id, zoneOwner: account,
            workspaceID: id)
    }

    private func validate(_ context: WorkspaceContext, in state: State) throws {
        guard context.container == containerIdentifier, context.zoneOwner == account,
            state.workspaces.contains(where: { $0.context.workspaceID == context.workspaceID })
        else {
            throw CollaborationError.invalidWorkspace
        }
    }

    private func load() throws -> State {
        guard FileManager.default.fileExists(atPath: file.path) else { return State() }
        return try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
    }

    private func persist(_ state: State) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
    }
}
