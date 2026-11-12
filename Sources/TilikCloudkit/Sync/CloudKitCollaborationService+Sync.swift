#if os(iOS)
//
//  CloudKitCollaborationService+Sync.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation
import CloudKit

extension CloudKitCollaborationService {
    public func changes(since snapshot: CollaborationSnapshot) async throws -> CollaborationDelta {
        var delta = CollaborationDelta()
        for scope in [WorkspaceContext.Scope.owner, .participant] {
            let result = try await databaseChanges(scope: scope, data: snapshot.databaseTokens[scope.rawValue])
            let deletedZones = Set(result.deleted)
            for workspace in snapshot.workspaces where workspace.context.scope == scope {
                let identifier = zoneID(workspace.context)
                if deletedZones.contains(identifier) || result.liveZones.map({ !$0.contains(identifier) }) == true {
                    delta.removedWorkspaces.insert(workspace.id)
                }
            }
            for zone in result.changed where zone.zoneName.hasPrefix(Self.zonePrefix) && !deletedZones.contains(zone) {
                do {
                    guard let workspace = try await workspace(in: zone, scope: scope) else {
                        for cached in snapshot.workspaces
                        where cached.context.scope == scope && zoneID(cached.context) == zone {
                            delta.removedWorkspaces.insert(cached.id)
                        }
                        continue
                    }
                    let changes = try await zoneChanges(workspace, data: snapshot.zoneTokens[workspace.id])
                    delta.workspaces.append(workspace)
                    delta.events[workspace.id] = changes.events
                    delta.deletions[workspace.id] = changes.deleted
                    delta.zoneTokens[workspace.id] = changes.token
                    if changes.reset { delta.resetZones.insert(workspace.id) }
                } catch {
                    if isAccessError(error) {
                        for workspace in snapshot.workspaces
                        where workspace.context.scope == scope && zoneID(workspace.context) == zone {
                            delta.removedWorkspaces.insert(workspace.id)
                        }
                    } else {
                        throw error
                    }
                }
            }
            // Advance the database token only after all zone pages have succeeded.
            delta.databaseTokens[scope.rawValue] = result.token
        }
        return delta
    }

    private func databaseChanges(
        scope: WorkspaceContext.Scope, data: Data?
    ) async throws -> (
        changed: Set<CKRecordZone.ID>, deleted: Set<CKRecordZone.ID>, token: Data, liveZones: Set<CKRecordZone.ID>?
    ) {
        var token = try unarchive(data)
        var changed: Set<CKRecordZone.ID> = []
        var deleted: Set<CKRecordZone.ID> = []
        do {
            var more = true
            while more {
                try Task.checkCancellation()
                let page = try await database(scope).databaseChanges(since: token)
                changed.formUnion(page.modifications.map(\.zoneID))
                deleted.formUnion(page.deletions.map(\.zoneID))
                token = page.changeToken
                more = page.moreComing
            }
        } catch let error as CKError where error.code == .changeTokenExpired && data != nil {
            return try await databaseChanges(scope: scope, data: nil)
        }
        // Token recovery also reconciles zones that no longer exist.
        var liveZones: Set<CKRecordZone.ID>?
        if data == nil {
            let zones = try await database(scope).allRecordZones()
            changed.formUnion(zones.map(\.zoneID))
            liveZones = Set(zones.map(\.zoneID))
        }
        guard let token else { throw CollaborationError.invalidWorkspace }
        return (changed, deleted, try archive(token), liveZones)
    }

    private func zoneChanges(
        _ workspace: TPAWorkspace, data: Data?
    ) async throws -> (events: [CollaborationEvent], deleted: Set<String>, token: Data, reset: Bool) {
        var token = try unarchive(data)
        var events: [CollaborationEvent] = []
        var deleted: Set<String> = []
        do {
            var more = true
            while more {
                try Task.checkCancellation()
                let page = try await database(workspace.context.scope).recordZoneChanges(
                    inZoneWith: zoneID(workspace.context), since: token,
                    desiredKeys: [TilikCloudKitSchema.Field.workspaceID, TilikCloudKitSchema.Field.payload]
                )
                for result in page.modificationResultsByID.values {
                    let record = try result.get().record
                    if [TilikCloudKitSchema.RecordType.hotspot, TilikCloudKitSchema.RecordType.ping, TilikCloudKitSchema.RecordType.response, TilikCloudKitSchema.RecordType.subzoneRun, TilikCloudKitSchema.RecordType.assignment, TilikCloudKitSchema.RecordType.assignmentResponse, TilikCloudKitSchema.RecordType.memberConnected].contains(record.recordType) {
                        let event = try decodeEvent(record)
                        guard event.workspaceID == workspace.context.workspaceID else {
                            throw CollaborationError.invalidWorkspace
                        }
                        events.append(event)
                    }
                }
                deleted.formUnion(page.deletions.map { $0.recordID.recordName })
                token = page.changeToken
                more = page.moreComing
            }
        } catch let error as CKError where error.code == .changeTokenExpired && data != nil {
            return try await zoneChanges(workspace, data: nil)
        }
        guard let token else { throw CollaborationError.invalidWorkspace }
        return (events, deleted, try archive(token), data == nil)
    }

    public func resetEvents(in workspace: TPAWorkspace) async throws {
        try await verifyOwner(workspace)
        // Enumerate by zone changes so reset never depends on missing query indexes.
        let snapshot = try await zoneChanges(workspace, data: nil)
        let identifiers = snapshot.events.filter { !snapshot.deleted.contains($0.id) }.map {
            CKRecord.ID(recordName: $0.id, zoneID: zoneID(workspace.context))
        }
        // Keep batches comfortably below CloudKit's operation limits; partial failures are surfaced.
        let batchSize = 100
        for start in stride(from: 0, to: identifiers.count, by: batchSize) {
            let batch = Array(identifiers[start..<min(start + batchSize, identifiers.count)])
            let result = try await container.privateCloudDatabase.modifyRecords(
                saving: [], deleting: batch, atomically: false)
            for result in result.deleteResults.values {
                do { try result.get() } catch let error as CKError where error.code == .unknownItem { continue }
            }
        }
        let remaining = try await zoneChanges(workspace, data: nil)
        guard remaining.events.allSatisfy({ remaining.deleted.contains($0.id) }) else { throw CollaborationError.busy }
    }
}

#endif
