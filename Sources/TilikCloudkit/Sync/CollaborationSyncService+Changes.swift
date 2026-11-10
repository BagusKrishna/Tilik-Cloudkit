//
//  CollaborationSyncService+Changes.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

extension CollaborationSyncService {
    public func apply(_ delta: CollaborationDelta) throws {
        guard var value = snapshot else { throw CancellationError() }
        for key in delta.removedWorkspaces {
            value.removeWorkspace(key)
            if value.deletingWorkspaceKeys?.contains(key) == true {
                value.pending.removeAll { $0.context.key == key }
                value.alertLedger = value.alertLedger.filter { !$0.key.hasPrefix(key + "|") }
                value.deletingWorkspaceKeys?.remove(key)
                value.unavailableWorkspaceKeys?.remove(key)
                value.dismissedUnavailableWorkspaceKeys?.remove(key)
            }
        }
        for workspace in delta.workspaces {
            value.unavailableWorkspaceKeys?.remove(workspace.id)
            value.dismissedUnavailableWorkspaceKeys?.remove(workspace.id)
            let initial = !value.bootstrappedWorkspaces.contains(workspace.id)
            value.workspaces.removeAll { $0.id == workspace.id }
            value.workspaces.append(workspace)
            if delta.resetZones.contains(workspace.id) { value.events[workspace.id] = [] }
            let deleted = delta.deletions[workspace.id, default: []]
            value.events[workspace.id, default: []].removeAll { deleted.contains($0.id) }
            for event in delta.events[workspace.id, default: []] where !deleted.contains(event.id) {
                value.events[workspace.id, default: []].removeAll { $0.id == event.id }
                value.events[workspace.id, default: []].append(event)
                if initial {
                    let key = CollaborationPolicy.alertKey(event: event, workspaceKey: workspace.id)
                    value.alertLedger[key] = .suppressed
                }
                value.pending.removeAll {
                    $0.context.key == workspace.id && $0.event.representsSameIntent(as: event)
                }
            }
            for index in value.pending.indices where value.pending[index].context.key == workspace.id {
                let mutation = value.pending[index]
                if mutation.event.kind == .observed, let target = mutation.event.hotspotID,
                    !value.events[workspace.id, default: []].contains(where: {
                        $0.id == target && $0.kind == .hotspot
                    })
                {
                    value.pending[index].state = .failed
                    value.pending[index].retryAt = nil
                    value.pending[index].errorMessage =
                        CollaborationError.targetUnavailable.localizedDescription
                }
            }
            value.bootstrappedWorkspaces.insert(workspace.id)
        }
        value.databaseTokens.merge(delta.databaseTokens) { _, new in new }
        value.zoneTokens.merge(delta.zoneTokens) { _, new in new }
        try commit(value)
        CollaborationDiagnostics.record("ui_applied")
    }

    public func deliverAlerts(session: UUID) async {
        guard let current = snapshot else { return }
        for workspace in current.workspaces {
            let workspaceEvents = current.events[workspace.id, default: []]
            let needsParticipantID = workspace.context.scope == .participant && workspaceEvents.contains { $0.kind == .assignment }
            let participantID: String? = needsParticipantID ? try? await cloud.officerParticipantID(in: workspace) : nil
            let needsMemberNames = workspace.context.scope == .owner && workspaceEvents.contains { event in
                guard event.kind == .assignmentResponse, event.senderID != current.accountID else { return false }
                return current.alertLedger[CollaborationPolicy.alertKey(event: event, workspaceKey: workspace.id)] == nil
            }
            let alertMembers: [CollaborationMember] = needsMemberNames ? (try? await cloud.members(of: workspace)) ?? [] : []
            let visibleHotspotIDs = Set(SubzoneRunProjector.activeHotspots(workspaceEvents).map(\.id))
            let knownHotspotIDs = Set(workspaceEvents.filter { $0.kind == .hotspot }.map(\.id))
            for event in current.events[workspace.id, default: []] {
                if event.kind == .assignment, workspace.context.scope == .participant {
                    // Retry on a later sync if CloudKit cannot provide the participant yet.
                    guard let participantID else { continue }
                    guard event.assignment?.recipientID == participantID else { continue }
                }
                if event.kind == .hotspot, !visibleHotspotIDs.contains(event.id) { continue }
                if event.kind == .observed, let target = event.hotspotID,
                   knownHotspotIDs.contains(target), !visibleHotspotIDs.contains(target) { continue }
                let key = CollaborationPolicy.alertKey(event: event, workspaceKey: workspace.id)
                let disposition = snapshot?.alertLedger[key]
                if disposition == .scheduled || disposition == .suppressed { continue }
                var body = alertBody(event, workspace.context.scope)
                if workspace.context.scope == .owner, event.kind == .assignmentResponse,
                   let task = event.assignment, let currentBody = body {
                    let member = alertMembers.first { $0.id == task.recipientID }
                    let name = member?.name ?? member?.email ?? "petugas"
                    body = event.inspectionReport == nil ? "\(currentBody) oleh \(name)" : "\(currentBody) dari \(name)"
                }
                if event.kind == .observed && body != nil {
                    let hotspots = current.events[workspace.id, default: []].filter { $0.kind == .hotspot }
                        .sorted {
                            ($0.clientCreatedAt, $0.id) < ($1.clientCreatedAt, $1.id)
                        }
                    if let index = hotspots.firstIndex(where: { $0.id == event.hotspotID }) {
                        body =
                            event.status == .unobserved
                            ? "Hotspot \(index + 1) perlu dipantau kembali"
                            : "Hotspot \(index + 1) sudah terpantau"
                    }
                }
                if let currentBody = body {
                    body = formatAlertBody(currentBody, event, workspace.context.scope)
                }
                if event.senderID == current.accountID || body == nil || event.hazard?.notifyRecipient == false {
                    do {
                        guard var value = snapshot else { return }
                        value.alertLedger[key] = .suppressed
                        try commit(value)
                    } catch { setMessage("Pencatatan notifikasi gagal. Periksa penyimpanan perangkat.") }
                    continue
                }
                do {
                    try ensureSession(session)
                    CollaborationDiagnostics.record("notification_enqueued", operation: event.id)
                    let route: [String: String] = event.kind == .assignmentResponse && workspace.context.scope == .owner
                        ? ["tilikRoute": "assignments", "workspaceID": workspace.context.workspaceID, "taskID": event.assignment?.id ?? ""] : [:]
                    let scheduled = try await alerts.schedule(
                        id: current.accountID + "|" + key, body: body ?? "", route: route)
                    try ensureSession(session)
                    guard var value = snapshot else { return }
                    value.alertLedger[key] = scheduled ? .scheduled : .suppressed
                    try commit(value)
                    CollaborationDiagnostics.record("schedule_ack", operation: event.id)
                } catch is CancellationError {
                    alerts.cancelPending()
                    return
                } catch {
                    guard generation == session, var value = snapshot else { return }
                    value.alertLedger[key] = .failed
                    try? commit(value)
                }
            }
        }
    }
}
