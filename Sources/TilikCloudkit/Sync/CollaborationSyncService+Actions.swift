import Foundation

extension CollaborationSyncService {
    /// Reserve the structural operation before awaiting an existing fetch/save.
    /// New writes cannot slip into reset/delete while it waits for that task.
    public func performStructural<Value>(
        waitForSync: Bool = true, _ operation: (UUID) async throws -> Value
    ) async throws -> Value {
        let session = generation
        guard !isStructuralOperationActive else { throw CollaborationError.busy }
        isStructuralOperationActive = true
        retryTask?.cancel()
        onChange?()
        defer {
            if generation == session {
                isStructuralOperationActive = false
                onChange?()
                scheduleRetry()
                if syncCompletedWhileStructural { notifySyncCompleted() }
                if synchronizationRequested {
                    requestSynchronization(reason: "structural_release")
                }
            }
        }
        if waitForSync, let task = syncTask {
            let previousRun = syncRunID
            _ = try await task.value
            try ensureSession(session)
            if syncRunID == previousRun {
                syncTask = nil
                syncRunID = nil
                // Retirement prevents a post-reset sync from coalescing onto a finished pre-reset task.
            }
        }
        try ensureSession(session)
        finishRetiredSync()
        let value = try await operation(session)
        try ensureSession(session)
        return value
    }

    public func selectWorkspace(_ workspace: TPAWorkspace) throws {
        guard var value = snapshot, value.workspaces.contains(workspace) else {
            throw CollaborationError.invalidWorkspace
        }
        if value.activeWorkspaceKeys == nil { value.activeWorkspaceKeys = [:] }
        value.activeWorkspaceKeys?[workspace.context.scope.rawValue] = workspace.id
        try commit(value)
    }

    public func createWorkspace(name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CollaborationError.invalidName }
        try await performStructural { session in
            guard let before = snapshot else { throw CollaborationError.accountUnavailable }
            // Refresh before create, including after an ambiguous previous attempt.
            let delta = try await cloud.changes(since: before)
            try ensureSession(session)
            try apply(delta)
            guard snapshot?.workspaces.contains(where: { $0.context.scope == .owner }) == false else {
                throw CollaborationError.workspaceExists
            }
            let workspace = try await cloud.createWorkspace(name: trimmed, accountID: before.accountID)
            try ensureSession(session)
            guard var value = snapshot else { throw CancellationError() }
            value.workspaces.append(workspace)
            if value.activeWorkspaceKeys == nil { value.activeWorkspaceKeys = [:] }
            value.activeWorkspaceKeys?["owner"] = workspace.id
            try commit(value)
        }
        try await synchronize()
    }

    public func rename(_ workspace: TPAWorkspace, name: String) async throws {
        try await performStructural { session in
            try requireOwner(workspace)
            let renamed = try await cloud.renameWorkspace(workspace, name: name)
            try ensureSession(session)
            guard var value = snapshot else { throw CancellationError() }
            for index in value.workspaces.indices
            where value.workspaces[index].context.workspaceID == workspace.context.workspaceID {
                let existing = value.workspaces[index]
                value.workspaces[index] = TPAWorkspace(
                    context: existing.context, name: renamed.name,
                    ownerAccountID: existing.ownerAccountID, schemaVersion: existing.schemaVersion)
            }
            try commit(value)
        }
        try await synchronize()
    }

    public func delete(_ workspace: TPAWorkspace) async throws {
        try await performStructural { session in
            try requireOwner(workspace)
            guard var value = snapshot else { throw CancellationError() }
            if value.deletingWorkspaceKeys == nil { value.deletingWorkspaceKeys = [] }
            value.deletingWorkspaceKeys?.insert(workspace.id)
            value.pending.removeAll { $0.context.key == workspace.id }
            try commit(value)
            // Marker survives ambiguous failures; no writes resume until deletion is reconciled/retried.
            try await cloud.deleteWorkspace(workspace)
            try ensureSession(session)
            guard var latest = snapshot else { throw CancellationError() }
            let related = latest.workspaces.filter {
                $0.context.container == workspace.context.container
                    && $0.context.workspaceID == workspace.context.workspaceID
            }
            for item in related {
                latest.removeWorkspace(item.id)
                latest.pending.removeAll { $0.context.key == item.id }
                latest.alertLedger = latest.alertLedger.filter { !$0.key.hasPrefix(item.id + "|") }
                latest.unavailableWorkspaceKeys?.remove(item.id)
                latest.dismissedUnavailableWorkspaceKeys?.remove(item.id)
            }
            latest.deletingWorkspaceKeys?.remove(workspace.id)
            latest.databaseTokens.removeValue(forKey: workspace.context.scope.rawValue)
            try commit(latest)
        }
        try await synchronize()
    }

    public func invite(_ workspace: TPAWorkspace) async throws -> CollaborationInvitation {
        // Share metadata is independent of the event fetch/outbox. Keep the structural
        // reservation so reset/delete cannot race, but do not wait for a slow refresh.
        try await performStructural(waitForSync: false) { session in
            try requireOwner(workspace)
            let url = try await cloud.invitation(for: workspace)
            try ensureSession(session)
            return url
        }
    }

    public func cancelInvitation(
        _ invitation: CollaborationInvitation, workspace: TPAWorkspace
    ) async throws -> CollaborationInvitationCancellation {
        try await performStructural(waitForSync: false) { session in
            try requireOwner(workspace)
            let result = try await cloud.cancelInvitation(invitation, workspace: workspace)
            try ensureSession(session)
            return result
        }
    }

    public func members(_ workspace: TPAWorkspace) async throws -> [CollaborationMember]? {
        let session = generation
        guard let accountID = snapshot?.accountID else { throw CollaborationError.accountUnavailable }
        try requireOwner(workspace)
        let value = try await cloud.members(of: workspace)
        try ensureSession(session)
        guard snapshot?.accountID == accountID else { throw CancellationError() }
        try requireOwner(workspace)
        return value
    }

    /// Notify only for a verified newly accepted invitation; do not repeat on refresh.
    public func notifyMemberConnected(_ member: CollaborationMember, in workspace: TPAWorkspace) async {
        guard workspace.context.scope == .owner, !member.isOwner,
              let account = snapshot?.accountID, workspace.ownerAccountID == account,
              snapshot?.workspaces.contains(workspace) == true else { return }
        let session = generation
        let key = workspace.id + "|member-connected:" + member.id
        let eventID = "member-connected-" + member.id
        if !(snapshot?.events[workspace.id, default: []].contains { $0.id == eventID } ?? false),
           !(snapshot?.pending.contains { $0.id == eventID } ?? false) {
            do {
                try enqueue(CollaborationEvent(id: eventID, workspaceID: workspace.context.workspaceID,
                                               kind: .memberConnected, senderID: account,
                                               senderRole: .operatorRole, memberID: member.id), in: workspace)
            } catch { CollaborationDiagnostics.failure("member_connected_history_failed", error: error) }
        }
        guard snapshot?.alertLedger[key] == nil else { return }
        let name = member.name ?? member.email ?? "petugas"
        do {
            let scheduled = try await alerts.schedule(id: account + "|" + key,
                body: "Berhasil terhubung dengan \(name).", route: [:])
            try ensureSession(session)
            guard var value = snapshot, value.accountID == account,
                  value.workspaces.contains(workspace) else { return }
            value.alertLedger[key] = scheduled ? .scheduled : .suppressed
            try commit(value)
        } catch is CancellationError { return }
        catch { CollaborationDiagnostics.failure("member_connected_notification_failed", error: error) }
    }

    public func revoke(_ memberID: String?, workspace: TPAWorkspace) async throws {
        try await performStructural { _ in
            try requireOwner(workspace)
            try await cloud.revoke(memberID: memberID, workspace: workspace)
        }
        try await synchronize()
    }

    public func join(_ url: URL) async throws {
        do {
            try await performStructural { _ in
                guard let account = snapshot?.accountID else { throw CollaborationError.accountUnavailable }
                try await cloud.join(url: url, accountID: account)
            }
        } catch {
            CollaborationDiagnostics.failure("share_accept_failed", error: error)
            throw error
        }
        // Acceptance can finish before the shared zone appears in a fresh fetch.
        // Retry only the fetch; a one-time invitation must never be accepted twice.
        for attempt in 0..<3 {
            do {
                try await synchronize()
                if snapshot?.workspaces.contains(where: { $0.context.scope == .participant }) == true {
                    return
                }
                CollaborationDiagnostics.record("accepted_share_not_visible")
                guard attempt < 2 else { throw CollaborationError.membershipPending }
            } catch {
                CollaborationDiagnostics.failure("post_accept_sync_failed", error: error)
                guard attempt < 2, !(error is CancellationError) else { throw error }
            }
            try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
        }
    }

    public func leave(_ workspace: TPAWorkspace) async throws {
        try await performStructural { session in
            guard let before = snapshot, workspace.context.scope == .participant,
                before.workspaces.contains(where: { $0.id == workspace.id })
            else { throw CollaborationError.invalidWorkspace }
            guard !before.pending.contains(where: { $0.context.key == workspace.id })
            else { throw CollaborationError.pendingChanges }
            try await cloud.leave(workspace, accountID: before.accountID)
            try ensureSession(session)
            guard var value = snapshot, value.accountID == before.accountID else {
                throw CancellationError()
            }
            value.removeWorkspace(workspace.id)
            value.unavailableWorkspaceKeys?.remove(workspace.id)
            value.dismissedUnavailableWorkspaceKeys?.remove(workspace.id)
            value.alertLedger = value.alertLedger.filter { !$0.key.hasPrefix(workspace.id + "|") }
            value.databaseTokens.removeValue(forKey: WorkspaceContext.Scope.participant.rawValue)
            try commit(value)
        }
        requestSynchronization(reason: "left_share")
    }

    public func reset(_ workspace: TPAWorkspace) async throws {
        try await performStructural { session in
            try requireOwner(workspace)
            guard var value = snapshot else { throw CancellationError() }
            guard value.deletingWorkspaceKeys?.contains(workspace.id) != true else {
                throw CollaborationError.busy
            }
            value.resetInProgress.insert(workspace.id)
            value.pending.removeAll { $0.context.key == workspace.id }
            try commit(value)
            try await cloud.resetEvents(in: workspace)
            try ensureSession(session)
            guard var latest = snapshot else { throw CancellationError() }
            latest.events[workspace.id] = []
            latest.zoneTokens.removeValue(forKey: workspace.id)
            latest.databaseTokens.removeValue(forKey: workspace.context.scope.rawValue)
            latest.resetInProgress.remove(workspace.id)
            try commit(latest)
        }
        try await synchronize()
    }

    public func requireOwner(_ workspace: TPAWorkspace) throws {
        guard let value = snapshot, workspace.context.scope == .owner,
            workspace.ownerAccountID == value.accountID,
            value.workspaces.contains(where: { $0.id == workspace.id })
        else { throw CollaborationError.notOwner }
    }
}
