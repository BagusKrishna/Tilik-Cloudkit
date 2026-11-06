//
//  CollaborationSyncService.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Owns sync beyond view lifetime. Presentation observes through its ViewModel.
@MainActor
public final class CollaborationSyncService {
    public private(set) var snapshot: CollaborationSnapshot?
    public private(set) var isSyncing = false
    public private(set) var hasLoadedWorkspaces = false
    public var isConnecting: Bool { connectionTask != nil }
    public var isStructuralOperationActive = false
    public private(set) var message: String?
    public var onChange: (() -> Void)?
    public var onSyncCompleted: (() -> Void)?

    public let cloud: CollaborationCloudServing
    public let store: CollaborationPersisting
    public let alerts: CollaborationAlertServing
    public let maximumPendingCount: Int
    let alertBody: (CollaborationEvent, WorkspaceContext.Scope) -> String?
    let formatAlertBody: (String, CollaborationEvent, WorkspaceContext.Scope) -> String
    public var generation = UUID()
    public var syncTask: Task<Bool, Error>?
    public var syncRunID: UUID?
    public var retryTask: Task<Void, Never>?
    public var syncRequestTask: Task<Void, Never>?
    public var needsCatchUp = false
    public var synchronizationRequested = false
    public var syncCompletedWhileStructural = false
    private var connectionTask: Task<Result<Bool, Error>, Never>?
    private var connectionRunID: UUID?
    private var subscriptionTask: Task<Void, Never>?

    public init(
        cloud: CollaborationCloudServing, store: CollaborationPersisting,
        alerts: CollaborationAlertServing, maximumPendingCount: Int,
        alertBody: @escaping (CollaborationEvent, WorkspaceContext.Scope) -> String? = CollaborationPolicy.alertBody,
        formatAlertBody: @escaping (String, CollaborationEvent, WorkspaceContext.Scope) -> String = { body, _, _ in body }
    ) {
        self.cloud = cloud
        self.store = store
        self.alerts = alerts
        self.maximumPendingCount = maximumPendingCount
        self.alertBody = alertBody
        self.formatAlertBody = formatAlertBody
    }

    @discardableResult
    public func connect() async -> Result<Bool, Error> {
        if let connectionTask, let connectionRunID {
            let result = await connectionTask.value
            finishConnection(connectionRunID)
            return result
        }
        let runID = UUID()
        connectionRunID = runID
        let task = Task<Result<Bool, Error>, Never> { @MainActor [self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<Bool, Error>, Never>) in
                var completed = false
                let operation = Task { await performConnection() }
                let timeout = Task { @MainActor [self] in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                    catch { return }
                    guard !completed else { return }
                    completed = true
                    operation.cancel()
                    // Retire late callbacks without discarding the persisted snapshot/outbox.
                    cancelSessionTasks()
                    let error = CollaborationError.connectionTimedOut
                    message = error.localizedDescription
                    CollaborationDiagnostics.failure("connection_timed_out", error: error)
                    onChange?()
                    continuation.resume(returning: .failure(error))
                }
                Task { @MainActor in
                    let result = await operation.value
                    guard !completed else { return }
                    completed = true
                    timeout.cancel()
                    continuation.resume(returning: result)
                }
            }
        }
        connectionTask = task
        onChange?()
        let result = await task.value
        finishConnection(runID)
        return result
    }

    private func finishConnection(_ runID: UUID) {
        if connectionRunID == runID {
            connectionTask = nil
            connectionRunID = nil
            onChange?()
        }
    }

    private func performConnection() async -> Result<Bool, Error> {
        var session = generation
        var appliedChanges = false
        var phase = "account"
        do {
            CollaborationDiagnostics.record("account_check_started")
            let account = try await cloud.accountID()
            try ensureSession(session)
            CollaborationDiagnostics.record("account_check_finished")
            if snapshot?.accountID != account {
                invalidateAccount()
                session = generation
                var loaded = try store.load(accountID: account)
                // Never resend potentially stale pre-restart intentions without review.
                for index in loaded.pending.indices { loaded.pending[index].state = .needsReview }
                try commit(loaded)
            }
            let current = generation
            phase = "workspace_sync"
            appliedChanges = try await synchronize()
            try ensureSession(current)
            registerSubscriptionsInBackground(session: current)
        } catch let error as CancellationError {
            return .failure(error)
        } catch {
            guard session == generation else { return .failure(CancellationError()) }
            CollaborationDiagnostics.failure("connection_failed.\(phase)", error: error)
            if case CollaborationError.accountUnavailable = error { invalidateAccount() }
            message = userMessage(error)
            onChange?()
            return .failure(error)
        }
        onChange?()
        return .success(appliedChanges)
    }

    public func invalidateAccount() {
        cancelSessionTasks()
        snapshot = nil
        hasLoadedWorkspaces = false
        message = nil
        alerts.cancelPending()
        onChange?()
    }

    private func cancelSessionTasks() {
        generation = UUID()
        syncTask?.cancel()
        retryTask?.cancel()
        syncRequestTask?.cancel()
        subscriptionTask?.cancel()
        subscriptionTask = nil
        syncTask = nil
        syncRunID = nil
        syncRequestTask = nil
        synchronizationRequested = false
        needsCatchUp = false
        syncCompletedWhileStructural = false
        isSyncing = false
        isStructuralOperationActive = false
    }

    private func registerSubscriptionsInBackground(session: UUID) {
        guard subscriptionTask == nil else { return }
        subscriptionTask = Task { @MainActor [self] in
            defer { if generation == session { subscriptionTask = nil } }
            do {
                try await cloud.registerSubscriptions()
                try ensureSession(session)
            } catch {
                guard generation == session, !Task.isCancelled else { return }
                CollaborationDiagnostics.failure("subscription_registration_failed", error: error)
                message = "Data terhubung, tetapi notifikasi perubahan belum aktif. Coba muat ulang."
                onChange?()
            }
        }
    }

    /// Concurrent callers await the actual catch-up result, not a fire-and-forget task.
    @discardableResult
    public func synchronize() async throws -> Bool {
        guard snapshot != nil else { throw CollaborationError.accountUnavailable }
        guard !isStructuralOperationActive else { throw CollaborationError.busy }
        if let syncTask {
            needsCatchUp = true
            return try await syncTask.value
        }
        let session = generation
        let runID = UUID()
        syncRunID = runID
        let task = Task { @MainActor [self] in
            var changed = false
            repeat {
                needsCatchUp = false
                try ensureSession(session)
                changed = try await drainOutbox(session: session) || changed
                guard let before = snapshot else { throw CancellationError() }
                let operation = UUID().uuidString
                CollaborationDiagnostics.record("fetch_started", operation: operation)
                let delta = try await cloud.changes(since: before)
                CollaborationDiagnostics.record("fetch_finished", operation: operation)
                try ensureSession(session)
                try apply(delta)
                hasLoadedWorkspaces = true
                changed =
                    changed || snapshot?.workspaces != before.workspaces || snapshot?.events != before.events
                    || snapshot?.pending != before.pending
                await deliverAlerts(session: session)
            } while needsCatchUp
            return changed
        }
        syncTask = task
        isSyncing = true
        onChange?()
        do {
            let result = try await task.value
            try ensureSession(session)
            // A structural action may already have retired this completed run.
            guard syncRunID == runID else { return result }
            syncTask = nil
            syncRunID = nil
            isSyncing = false
            message = nil
            scheduleRetry()
            onChange?()
            notifySyncCompleted()
            return result
        } catch {
            if session == generation && syncRunID == runID {
                syncTask = nil
                syncRunID = nil
                isSyncing = false
                message = userMessage(error)
                scheduleRetry()
                onChange?()
            }
            throw error
        }
    }

    public func enqueue(_ event: CollaborationEvent, in workspace: TPAWorkspace,
                 attachments: HotspotAttachmentPaths? = nil,
                 rgbJPEGPath: String? = nil,
                 inspectionPhotoPath: String? = nil) throws {
        guard !isStructuralOperationActive else { throw CollaborationError.busy }
        guard var value = snapshot, value.workspaces.contains(workspace) else {
            throw CollaborationError.accountUnavailable
        }
        guard !value.resetInProgress.contains(workspace.id),
            value.deletingWorkspaceKeys?.contains(workspace.id) != true
        else { throw CollaborationError.busy }
        guard value.pending.count < maximumPendingCount else { throw CollaborationError.queueFull }
        guard !value.pending.contains(where: { $0.id == event.id }) else { return }
        guard event.workspaceID == workspace.context.workspaceID else {
            throw CollaborationError.invalidWorkspace
        }
        guard event.senderID == value.accountID,
            event.senderRole == (workspace.context.scope == .owner ? .operatorRole : .officer)
        else {
            throw CollaborationError.notOwner
        }
        if (event.kind == .hotspot || event.kind == .subzoneRun)
            && (workspace.context.scope != .owner || workspace.ownerAccountID != value.accountID)
        {
            throw CollaborationError.notOwner
        }
        if event.kind == .subzoneRun {
            guard let run = event.subzoneRun, run.hotspotCount >= 0,
                  !run.sessionID.isEmpty, !run.zoneID.isEmpty, !run.subzoneID.isEmpty,
                  run.eventIDsDigest.count == 64
            else { throw CollaborationError.invalidWorkspace }
        }
        if let attachments {
            guard event.kind == .hotspot, event.hotspotDetails?.source == .thermal,
                  attachments.urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
            else { throw CollaborationError.targetUnavailable }
        }
        if let rgbJPEGPath {
            guard event.kind == .hotspot, event.hotspotDetails?.source == .rgb,
                  FileManager.default.fileExists(atPath: rgbJPEGPath)
            else { throw CollaborationError.targetUnavailable }
        }
        if let inspectionPhotoPath {
            guard event.kind == .observed, event.inspectionReport?.hasPhoto == true,
                  FileManager.default.fileExists(atPath: inspectionPhotoPath)
            else { throw CollaborationError.targetUnavailable }
        }
        if event.kind == .observed {
            guard workspace.context.scope == .participant || workspace.ownerAccountID == value.accountID,
                value.events[workspace.id, default: []].contains(where: {
                    $0.id == event.hotspotID && $0.kind == .hotspot
                })
            else {
                throw CollaborationError.targetUnavailable
            }
        }
        var mutation = PendingMutation(
            accountID: value.accountID, context: workspace.context, event: event, attachments: attachments)
        mutation.rgbJPEGPath = rgbJPEGPath
        mutation.inspectionPhotoPath = inspectionPhotoPath
        value.pending.append(mutation)
        try commit(value)
        CollaborationDiagnostics.record("local_pending_applied", operation: event.id)
        requestSynchronization(reason: "new_mutation")
    }

    public func retry(_ id: String) throws {
        guard var value = snapshot, let index = value.pending.firstIndex(where: { $0.id == id }),
            value.workspaces.contains(where: { $0.id == value.pending[index].context.key })
        else {
            throw CollaborationError.targetUnavailable
        }
        guard !isStructuralOperationActive,
            !value.resetInProgress.contains(value.pending[index].context.key),
            value.deletingWorkspaceKeys?.contains(value.pending[index].context.key) != true
        else { throw CollaborationError.busy }
        if let target = value.pending[index].event.hotspotID {
            guard
                value.events[value.pending[index].context.key, default: []].contains(where: {
                    $0.id == target && $0.kind == .hotspot
                })
            else { throw CollaborationError.targetUnavailable }
        }
        value.pending[index].state = .queued
        value.pending[index].retryAt = nil
        try commit(value)
        requestSynchronization(reason: "manual_retry")
    }

    public func finishRetiredSync() {
        if syncTask == nil { isSyncing = false }
    }

    public func commit(_ value: CollaborationSnapshot) throws {
        try store.save(value)
        let confirmed = Set(value.events.values.flatMap { $0.map(\.id) })
        for old in snapshot?.pending ?? [] where (old.attachments != nil || old.rgbJPEGPath != nil
            || old.inspectionPhotoPath != nil)
            && !value.pending.contains(where: { $0.id == old.id }) && confirmed.contains(old.id) {
            if let url = old.attachments?.urls.first?.deletingLastPathComponent() {
                try? FileManager.default.removeItem(at: url)
            }
            if let path = old.rgbJPEGPath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
            }
            // Confirmed by CloudKit: the outbox copy of the inspection photo is no longer needed.
            if let path = old.inspectionPhotoPath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
            }
        }
        snapshot = value
        onChange?()
    }

    public func ensureSession(_ session: UUID) throws {
        try Task.checkCancellation()
        guard generation == session else { throw CancellationError() }
    }

    public func userMessage(_ error: Error) -> String {
        if let error = error as? CollaborationError { return error.localizedDescription }
        if error is CancellationError { return "Pembaruan dibatalkan. Muat ulang untuk melanjutkan." }
        return cloud.message(for: error)
    }

    public func setMessage(_ text: String) {
        message = text
        onChange?()
    }

    public func dismissUnavailableWorkspaceNotice(scope: WorkspaceContext.Scope) throws {
        guard var value = snapshot else { throw CollaborationError.accountUnavailable }
        let keys = value.unavailableWorkspaceKeys ?? []
        let matching = keys.filter { WorkspaceContext.scope(from: $0) == scope }
        guard !matching.isEmpty else { return }
        if value.dismissedUnavailableWorkspaceKeys == nil { value.dismissedUnavailableWorkspaceKeys = [] }
        value.dismissedUnavailableWorkspaceKeys?.formUnion(matching)
        try commit(value)
    }

    /// Retains automatic work through structural operations and combines concurrent triggers.
    public func requestSynchronization(reason: String) {
        CollaborationDiagnostics.record("sync_requested.\(reason)")
        guard snapshot != nil else { return }
        synchronizationRequested = true
        guard !isStructuralOperationActive, syncRequestTask == nil else { return }
        syncRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainSynchronizationRequests()
        }
    }

    private func drainSynchronizationRequests() async {
        while synchronizationRequested && !isStructuralOperationActive {
            synchronizationRequested = false
            do {
                _ = try await synchronize()
            } catch is CancellationError {
                break
            } catch let error as CollaborationError {
                if case .busy = error { synchronizationRequested = true }
                break
            } catch {
                // synchronize() records the visible error and installs its retry policy.
                break
            }
            if needsCatchUp {
                needsCatchUp = false
                synchronizationRequested = true
            }
        }
        syncRequestTask = nil
        if synchronizationRequested && !isStructuralOperationActive {
            requestSynchronization(reason: "deferred_request")
        }
    }

    public func notifySyncCompleted() {
        guard !isStructuralOperationActive else {
            syncCompletedWhileStructural = true
            return
        }
        syncCompletedWhileStructural = false
        onSyncCompleted?()
    }

    private func drainOutbox(session: UUID) async throws -> Bool {
        let pending = snapshot?.pending ?? []
        var changed = false
        for mutation in pending {
            try ensureSession(session)
            guard let current = snapshot, mutation.accountID == current.accountID,
                current.workspaces.contains(where: { $0.id == mutation.context.key }),
                !current.resetInProgress.contains(mutation.context.key),
                current.deletingWorkspaceKeys?.contains(mutation.context.key) != true
            else { continue }
            if let target = mutation.event.hotspotID,
                !current.events[mutation.context.key, default: []].contains(where: {
                    $0.id == target && $0.kind == .hotspot
                })
            {
                continue
            }
            if mutation.state == .needsReview || mutation.state == .sending {
                if let accepted = try await cloud.reconcile(mutation) {
                    try ensureSession(session)
                    try acknowledge(accepted, mutation: mutation)
                    changed = true
                }
                continue
            }
            guard mutation.state == .queued || (mutation.state == .failed && mutation.retryAt != nil)
            else { continue }
            if let retryAt = mutation.retryAt, retryAt > Date() { continue }
            var value = current
            guard let index = value.pending.firstIndex(where: { $0.id == mutation.id }) else { continue }
            value.pending[index].state = .sending
            value.pending[index].attempts += 1
            try commit(value)
            do {
                CollaborationDiagnostics.record("save_started", operation: mutation.id)
                let accepted = try await cloud.save(mutation)
                try ensureSession(session)
                try acknowledge(accepted, mutation: mutation)
                CollaborationDiagnostics.record("save_ack", operation: mutation.id)
                changed = true
            } catch {
                try ensureSession(session)
                guard var latest = snapshot,
                    let index = latest.pending.firstIndex(where: { $0.id == mutation.id })
                else { continue }
                latest.pending[index].state = .failed
                latest.pending[index].errorMessage = userMessage(error)
                latest.pending[index].retryAt = cloud.retryDate(for: error)
                if cloud.isAccessError(error) { latest.removeWorkspace(mutation.context.key) }
                try commit(latest)
                CollaborationDiagnostics.failure(
                    "save_failed", error: error, operation: mutation.id,
                    retryAfter: latest.pending[index].retryAt.map { max($0.timeIntervalSinceNow, 0) }
                )
            }
        }
        return changed
    }

    private func acknowledge(_ event: CollaborationEvent, mutation: PendingMutation) throws {
        guard var value = snapshot else { throw CancellationError() }
        value.events[mutation.context.key, default: []].removeAll { $0.id == event.id }
        value.events[mutation.context.key, default: []].append(event)
        value.pending.removeAll { $0.id == mutation.id }
        try commit(value)
    }

    public func scheduleRetry() {
        retryTask?.cancel()
        guard let earliest = snapshot?.pending.compactMap(\.retryAt).min() else { return }
        let session = generation
        retryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(earliest.timeIntervalSinceNow, 1) * 1_000_000_000))
                guard let self else { return }
                try self.ensureSession(session)
                self.requestSynchronization(reason: "network_retry")
            } catch { return }
        }
    }
}
