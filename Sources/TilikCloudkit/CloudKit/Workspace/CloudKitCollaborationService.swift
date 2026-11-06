#if os(iOS)
//
//  CloudKitCollaborationService.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import CloudKit
import Foundation

/// Direct CloudKit adapter; sharing never uses the Public Database.
@MainActor
public final class CloudKitCollaborationService: CollaborationCloudServing {
    public let containerIdentifier: String
    let evidence: CloudKitEvidenceHandling
    let container: CKContainer
    static let zonePrefix = "TilikTPA_"

    public init(containerIdentifier: String, evidence: CloudKitEvidenceHandling) {
        self.evidence = evidence
        self.containerIdentifier = containerIdentifier
        container = CKContainer(identifier: containerIdentifier)
    }

    public func accountID() async throws -> String {
        do {
            guard try await container.accountStatus() == .available else {
                throw CollaborationError.accountUnavailable
            }
        } catch {
            CollaborationDiagnostics.failure("icloud_account_status_failed", error: error)
            throw error
        }
        do {
            return try await container.userRecordID().recordName
        } catch {
            CollaborationDiagnostics.failure("icloud_user_record_failed", error: error)
            throw error
        }
    }

    public func createWorkspace(name: String, accountID: String) async throws -> TPAWorkspace {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CollaborationError.invalidName
        }
        guard try await self.accountID() == accountID else { throw CancellationError() }
        let zones = try await container.privateCloudDatabase.allRecordZones()
        let existing = try await workspaces(in: zones, scope: .owner)
        guard existing.isEmpty else { throw CollaborationError.workspaceExists }
        let identifier = UUID().uuidString
        let zone = CKRecordZone(zoneName: Self.zonePrefix + identifier)
        let context = WorkspaceContext(
            container: containerIdentifier, scope: .owner, zoneName: zone.zoneID.zoneName,
            zoneOwner: zone.zoneID.ownerName, workspaceID: identifier
        )
        let workspace = TPAWorkspace(
            context: context, name: name, ownerAccountID: accountID, schemaVersion: 1)
        _ = try await container.privateCloudDatabase.save(zone)
        let record = CKRecord(recordType: TilikCloudKitSchema.RecordType.workspace, recordID: rootID(context))
        record[TilikCloudKitSchema.Field.workspaceID] = identifier as CKRecordValue
        record[TilikCloudKitSchema.Field.name] = name as CKRecordValue
        record[TilikCloudKitSchema.Field.ownerAccountID] = accountID as CKRecordValue
        record[TilikCloudKitSchema.Field.schemaVersion] = 1 as CKRecordValue
        // Persist the zone-wide share with the root record. Adding a participant
        // to a newly constructed, unsaved zone share traps inside CloudKit.
        let share = CKShare(recordZoneID: zone.zoneID)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = name as CKRecordValue
        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [record, share], deleting: [], atomically: true)
        guard let rootResult = result.saveResults[record.recordID],
            let shareResult = result.saveResults[share.recordID]
        else { throw CollaborationError.invalidShare }
        _ = try rootResult.get()
        _ = try shareResult.get()
        return workspace
    }

    public func renameWorkspace(_ workspace: TPAWorkspace, name: String) async throws -> TPAWorkspace {
        try await verifyOwner(workspace)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CollaborationError.invalidName }
        let root = try await container.privateCloudDatabase.record(for: rootID(workspace.context))
        root[TilikCloudKitSchema.Field.name] = trimmed as CKRecordValue
        var records = [root]
        if let share = try await fetchShare(workspace) {
            share[CKShare.SystemFieldKey.title] = trimmed as CKRecordValue
            records.append(share)
        }
        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: records, deleting: [], atomically: true)
        for saved in result.saveResults.values { _ = try saved.get() }
        guard let savedRoot = result.saveResults[root.recordID] else {
            throw CollaborationError.invalidWorkspace
        }
        return try decodeWorkspace(savedRoot.get(), scope: .owner)
    }

    public func deleteWorkspace(_ workspace: TPAWorkspace) async throws {
        // Check the live account even for an idempotent retry after an ambiguous zone deletion.
        guard workspace.context.container == containerIdentifier, workspace.context.scope == .owner,
            try await accountID() == workspace.ownerAccountID
        else { throw CollaborationError.notOwner }
        do {
            try await verifyOwner(workspace)
            _ = try await container.privateCloudDatabase.deleteRecordZone(
                withID: zoneID(workspace.context))
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
            return
        }
    }

    public func save(_ mutation: PendingMutation) async throws -> CollaborationEvent {
        guard try await accountID() == mutation.accountID else { throw CancellationError() }
        let database = database(mutation.context.scope)
        let root = try await database.record(for: rootID(mutation.context))
        guard root[TilikCloudKitSchema.Field.workspaceID] as? String == mutation.event.workspaceID else {
            throw CollaborationError.invalidWorkspace
        }
        if mutation.context.scope == .owner {
            guard root[TilikCloudKitSchema.Field.ownerAccountID] as? String == mutation.accountID else {
                throw CollaborationError.notOwner
            }
        }
        if let existing = try await reconcile(mutation) { return existing }
        if mutation.event.kind == .observed {
            guard let target = mutation.event.hotspotID else {
                throw CollaborationError.targetUnavailable
            }
            do {
                let record = try await database.record(
                    for: CKRecord.ID(recordName: target, zoneID: zoneID(mutation.context)))
                guard record.recordType == TilikCloudKitSchema.RecordType.hotspot,
                    record[TilikCloudKitSchema.Field.workspaceID] as? String == mutation.context.workspaceID
                else {
                    throw CollaborationError.targetUnavailable
                }
            } catch let error as CKError where error.code == .unknownItem {
                throw CollaborationError.targetUnavailable
            }
        }
        let record = try encode(mutation.event, context: mutation.context)
        if let attachments = mutation.attachments {
            guard attachments.urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
            else { throw CollaborationError.targetUnavailable }
            record[TilikCloudKitSchema.Field.thermalImage] = CKAsset(fileURL: attachments.urls[0])
            record[TilikCloudKitSchema.Field.rgbImage] = CKAsset(fileURL: attachments.urls[1])
        }
        if let rgbJPEGPath = mutation.rgbJPEGPath {
            guard FileManager.default.fileExists(atPath: rgbJPEGPath) else {
                throw CollaborationError.targetUnavailable
            }
            record[TilikCloudKitSchema.Field.rgbImage] = CKAsset(fileURL: URL(fileURLWithPath: rgbJPEGPath))
        }
        if let photoPath = mutation.inspectionPhotoPath {
            // Petugas' check photo rides on the same TilikResponse record.
            guard mutation.event.kind == .observed, FileManager.default.fileExists(atPath: photoPath)
            else { throw CollaborationError.targetUnavailable }
            record[TilikCloudKitSchema.Field.inspectionPhoto] = CKAsset(fileURL: URL(fileURLWithPath: photoPath))
        }
        do {
            return try decodeEvent(await database.save(record))
        } catch let error as CKError where error.code == .serverRecordChanged {
            // An earlier ambiguous write may have reached the server.
            guard let accepted = try await reconcile(mutation) else { throw error }
            return accepted
        }
    }

    public func reconcile(_ mutation: PendingMutation) async throws -> CollaborationEvent? {
        let recordID = CKRecord.ID(recordName: mutation.id, zoneID: zoneID(mutation.context))
        do {
            let record = try await database(mutation.context.scope).record(for: recordID)
            let event = try decodeEvent(record)
            if mutation.attachments != nil {
                guard record[TilikCloudKitSchema.Field.thermalImage] is CKAsset, record[TilikCloudKitSchema.Field.rgbImage] is CKAsset else {
                    throw CollaborationError.conflictingEvent
                }
            }
            if mutation.rgbJPEGPath != nil, record[TilikCloudKitSchema.Field.rgbImage] as? CKAsset == nil {
                throw CollaborationError.conflictingEvent
            }
            if mutation.inspectionPhotoPath != nil {
                // A response saved without its photo is not a finished report.
                guard record[TilikCloudKitSchema.Field.inspectionPhoto] is CKAsset else { throw CollaborationError.conflictingEvent }
            }
            if !event.representsSameIntent(as: mutation.event) {
                guard mutation.context.scope == .owner,
                      mutation.event.repairsMissingThermalTemperature(in: event)
                else { throw CollaborationError.conflictingEvent }
                record[TilikCloudKitSchema.Field.payload] = try JSONEncoder().encode(mutation.event) as CKRecordValue
                return try decodeEvent(await database(mutation.context.scope).save(record))
            }
            return event
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    public func invitation(for workspace: TPAWorkspace) async throws -> CollaborationInvitation {
        guard #available(iOS 18.0, *) else { throw CollaborationError.invitationRequiresNewerOS }
        #if targetEnvironment(simulator)
            // Unsigned Simulator builds cannot carry this entitlement.
            throw CollaborationError.oneTimeLinksUnavailable
        #else
            try await verifyOwner(workspace)
            let share: CKShare
            if let existing = try await fetchShare(workspace) {
                share = existing
            } else {
                // Existing TPA records created before this fix have no CKShare yet.
                // Save the empty share before adding a one-time participant.
                let created = CKShare(recordZoneID: zoneID(workspace.context))
                created.publicPermission = .none
                created[CKShare.SystemFieldKey.title] = workspace.name as CKRecordValue
                guard let saved = try await container.privateCloudDatabase.save(created) as? CKShare
                else { throw CollaborationError.invalidShare }
                share = saved
            }
            share.publicPermission = .none
            share[CKShare.SystemFieldKey.title] = workspace.name as CKRecordValue
            // A pending one-time URL is stable while its participant remains on the share.
            // Do not add the same participant again or make an unnecessary CloudKit save.
            if let existing = share.participants.lazy.compactMap({ participant -> CollaborationInvitation? in
                guard participant.role != .owner, participant.acceptanceStatus == .pending else {
                    return nil
                }
                guard let url = share.__oneTimeURL(forParticipantID: participant.participantID) else { return nil }
                return CollaborationInvitation(
                    workspaceID: workspace.id, participantID: participant.participantID, url: url)
            }).first {
                return existing
            }
            let participant = CKShare.Participant.oneTimeURLParticipant()
            participant.permission = .readWrite
            share.addParticipant(participant)
            guard let saved = try await container.privateCloudDatabase.save(share) as? CKShare,
                let url = saved.__oneTimeURL(forParticipantID: participant.participantID)
            else { throw CollaborationError.invalidShare }
            return CollaborationInvitation(
                workspaceID: workspace.id, participantID: participant.participantID, url: url)
        #endif
    }

    public func members(of workspace: TPAWorkspace) async throws -> [CollaborationMember]? {
        try await verifyOwner(workspace)
        guard let share = try await fetchShare(workspace) else { return nil }
        return share.participants.filter {
            $0.role == .owner || $0.acceptanceStatus == .accepted
        }.map { participant in
            let identity = participant.userIdentity
            let name = identity.nameComponents.map { PersonNameComponentsFormatter().string(from: $0) }
            let permission: CollaborationMember.Permission
            switch participant.permission {
            case .readOnly: permission = .readOnly
            case .readWrite: permission = .readWrite
            default: permission = .unknown
            }
            return CollaborationMember(
                id: participant.participantID, name: name, email: identity.lookupInfo?.emailAddress,
                permission: permission, isOwner: participant.role == .owner
            )
        }
    }

    public func cancelInvitation(
        _ invitation: CollaborationInvitation, workspace: TPAWorkspace
    ) async throws -> CollaborationInvitationCancellation {
        try await verifyOwner(workspace)
        guard invitation.workspaceID == workspace.id else { throw CollaborationError.invalidShare }
        for attempt in 0..<2 {
            guard let share = try await fetchShare(workspace),
                let participant = share.participants.first(where: { $0.participantID == invitation.participantID })
            else { return .missing }
            if participant.acceptanceStatus == .accepted { return .accepted }
            guard participant.role != .owner else { return .missing }
            share.removeParticipant(participant)
            do {
                _ = try await container.privateCloudDatabase.save(share)
                return .cancelled
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                continue
            }
        }
        throw CollaborationError.invalidShare
    }

    public func revoke(memberID: String?, workspace: TPAWorkspace) async throws {
        try await verifyOwner(workspace)
        guard let share = try await fetchShare(workspace) else { return }
        if let memberID {
            guard
                let participant = share.participants.first(where: {
                    $0.participantID == memberID && $0.role != .owner
                })
            else {
                throw CollaborationError.invalidShare
            }
            share.removeParticipant(participant)
            _ = try await container.privateCloudDatabase.save(share)
        } else {
            _ = try await container.privateCloudDatabase.deleteRecord(withID: share.recordID)
        }
    }

    public func join(url: URL, accountID: String) async throws {
        let metadata = try await container.shareMetadata(for: url)
        try await accept(metadata, accountID: accountID)
    }

    public func leave(_ workspace: TPAWorkspace, accountID: String) async throws {
        guard workspace.context.container == containerIdentifier,
            workspace.context.scope == .participant,
            workspace.ownerAccountID != accountID,
            try await self.accountID() == accountID
        else { throw CollaborationError.invalidWorkspace }
        let shareID = CKRecord.ID(
            recordName: CKRecordNameZoneWideShare, zoneID: zoneID(workspace.context))
        // Deleting the share in the participant's shared database leaves the share;
        // the owner's private zone and other participants remain intact.
        do {
            _ = try await container.sharedCloudDatabase.deleteRecord(withID: shareID)
        } catch let error as CKError where [.unknownItem, .zoneNotFound, .userDeletedZone].contains(error.code) {
            // The server already removed this membership (for example after an ambiguous retry).
        }
    }

    public func accept(_ metadata: CKShare.Metadata, accountID: String) async throws {
        guard metadata.containerIdentifier == containerIdentifier,
            metadata.share.recordID.zoneID.zoneName.hasPrefix(Self.zonePrefix)
        else {
            throw CollaborationError.invalidShare
        }
        guard metadata.participantRole != .owner,
            metadata.ownerIdentity.userRecordID?.recordName != accountID
        else { throw CollaborationError.ownInvitation }
        let zones = try await container.sharedCloudDatabase.allRecordZones()
        let memberships = try await workspaces(in: zones, scope: .participant)
        let requested = metadata.share.recordID.zoneID
        guard
            CollaborationPolicy.canJoin(
                existing: memberships, requestedZone: requested.zoneName, owner: requested.ownerName)
        else {
            throw CollaborationError.alreadyJoined
        }
        guard try await self.accountID() == accountID else { throw CancellationError() }
        if metadata.participantStatus != .accepted { _ = try await container.accept(metadata) }
    }

    public func registerSubscriptions() async throws {
        for scope in [WorkspaceContext.Scope.owner, .participant] {
            let subscription = CKDatabaseSubscription(
                subscriptionID: "tilik-collaboration-\(scope.rawValue)-v1")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database(scope).save(subscription)
        }
    }

    public func retryDate(for error: Error) -> Date? {
        guard let error = error as? CKError else { return nil }
        switch error.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return Date().addingTimeInterval(max(error.retryAfterSeconds ?? 30, 1))
        default: return nil
        }
    }

    public func isAccessError(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        return [.permissionFailure, .zoneNotFound, .userDeletedZone].contains(error.code)
    }

    public func message(for error: Error) -> String {
        guard let error = error as? CKError else {
            return "Penyimpanan atau pembaruan data gagal. Periksa ruang penyimpanan dan coba lagi."
        }
        switch error.code {
        case .notAuthenticated:
            return "Akun iCloud belum siap. Periksa akun di Pengaturan, lalu muat ulang."
        case .badContainer:
            return "Container iCloud build ini tidak tersedia atau belum diizinkan. Periksa container di Signing & Capabilities dan provisioning profile."
        case .unknownItem:
            return "Data iCloud yang diminta tidak ditemukan. Coba muat ulang koneksi TPA."
        case .quotaExceeded: return "Penyimpanan iCloud penuh. Kosongkan ruang, lalu coba kiriman lagi."
        case .permissionFailure, .zoneNotFound, .userDeletedZone:
            return "Akses TPA tidak tersedia atau telah dicabut. Minta operator memeriksa akses Anda."
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return
                "Koneksi iCloud tertunda. Data lokal tetap tersimpan; periksa koneksi atau coba lagi nanti."
        default:
            return "Pembaruan iCloud belum selesai. Muat ulang atau hubungi operator jika berulang."
        }
    }

    public func database(_ scope: WorkspaceContext.Scope) -> CKDatabase {
        scope == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    public func zoneID(_ context: WorkspaceContext) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: context.zoneName, ownerName: context.zoneOwner)
    }

    public func rootID(_ context: WorkspaceContext) -> CKRecord.ID {
        CKRecord.ID(recordName: "workspace", zoneID: zoneID(context))
    }

    public func verifyOwner(_ workspace: TPAWorkspace) async throws {
        guard workspace.context.container == containerIdentifier, workspace.context.scope == .owner
        else {
            throw CollaborationError.notOwner
        }
        let user = try await accountID()
        let root = try await container.privateCloudDatabase.record(for: rootID(workspace.context))
        guard root[TilikCloudKitSchema.Field.ownerAccountID] as? String == user else { throw CollaborationError.notOwner }
    }

    public func fetchShare(_ workspace: TPAWorkspace) async throws -> CKShare? {
        let identifier = CKRecord.ID(
            recordName: CKRecordNameZoneWideShare, zoneID: zoneID(workspace.context))
        do {
            let record = try await container.privateCloudDatabase.record(for: identifier)
            guard let share = record as? CKShare else { throw CollaborationError.invalidShare }
            return share
        } catch let error as CKError where error.code == .unknownItem {
            // Only this specific missing CKShare maps to “not sharing”.
            return nil
        }
    }

    public func workspaces(in zones: [CKRecordZone], scope: WorkspaceContext.Scope) async throws
        -> [TPAWorkspace]
    {
        var result: [TPAWorkspace] = []
        for zone in zones where zone.zoneID.zoneName.hasPrefix(Self.zonePrefix) {
            if let workspace = try await workspace(in: zone.zoneID, scope: scope) {
                result.append(workspace)
            }
        }
        return result
    }

    /// Zone creation can succeed before the atomic workspace/share save fails.
    /// An absent root is not a TPA; leave that zone on the server and keep loading others.
    public func workspace(in zone: CKRecordZone.ID, scope: WorkspaceContext.Scope) async throws -> TPAWorkspace? {
        let record: CKRecord
        do {
            record = try await database(scope).record(
                for: CKRecord.ID(recordName: "workspace", zoneID: zone))
        } catch let error as CKError where error.code == .unknownItem {
            CollaborationDiagnostics.failure("workspace_root_missing.\(scope.rawValue)", error: error)
            return nil
        }
        return try decodeWorkspace(record, scope: scope)
    }
}

#endif
