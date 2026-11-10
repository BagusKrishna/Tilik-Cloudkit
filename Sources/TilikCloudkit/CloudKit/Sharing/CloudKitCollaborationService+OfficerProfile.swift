#if os(iOS)
import CloudKit
import Foundation

extension CloudKitCollaborationService {
    private func officerRecordID(_ prefix: String, participantID: String, workspace: TPAWorkspace) -> CKRecord.ID {
        CKRecord.ID(recordName: prefix + participantID, zoneID: zoneID(workspace.context))
    }

    private func participantShare(_ workspace: TPAWorkspace) async throws -> CKShare {
        guard workspace.context.scope == .participant else { throw CollaborationError.invalidWorkspace }
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(workspace.context))
        guard let share = try await database(.participant).record(for: id) as? CKShare,
              share.currentUserParticipant?.acceptanceStatus == .accepted else { throw CollaborationError.invalidShare }
        return share
    }

    public func officerEmail(in workspace: TPAWorkspace) async throws -> String? {
        let share = try await participantShare(workspace)
        guard let participant = share.currentUserParticipant else { throw CollaborationError.invalidShare }
        if let email = participant.userIdentity.lookupInfo?.emailAddress, !email.isEmpty { return email }
        let id = officerRecordID("officer-identity-", participantID: participant.participantID, workspace: workspace)
        do {
            let record = try await database(.participant).record(for: id)
            guard record.creatorUserRecordID?.recordName == workspace.ownerAccountID,
                  record.lastModifiedUserRecordID?.recordName == workspace.ownerAccountID else { return nil }
            return record[TilikCloudKitSchema.Field.email] as? String
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }

    public func saveOfficerProfile(name: String, email: String?, in workspace: TPAWorkspace) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CollaborationError.invalidName }
        let share = try await participantShare(workspace)
        guard let participant = share.currentUserParticipant else { throw CollaborationError.invalidShare }
        let id = officerRecordID("officer-profile-", participantID: participant.participantID, workspace: workspace)
        let db = database(.participant)
        let record: CKRecord
        do { record = try await db.record(for: id) }
        catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: TilikCloudKitSchema.RecordType.officerProfile, recordID: id)
        }
        record[TilikCloudKitSchema.Field.participantID] = participant.participantID as CKRecordValue
        record[TilikCloudKitSchema.Field.name] = name as CKRecordValue
        record[TilikCloudKitSchema.Field.email] = email?.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue?
        _ = try await db.save(record)
    }

    func officerDetails(for participant: CKShare.Participant, workspace: TPAWorkspace) async -> (String?, String?) {
        let db = database(.owner)
        let participantID = participant.participantID
        let email = participant.userIdentity.lookupInfo?.emailAddress
        if let email, !email.isEmpty {
            let id = officerRecordID("officer-identity-", participantID: participantID, workspace: workspace)
            do {
                let record: CKRecord
                do { record = try await db.record(for: id) }
                catch let error as CKError where error.code == .unknownItem {
                    record = CKRecord(recordType: TilikCloudKitSchema.RecordType.officerIdentity, recordID: id)
                }
                if record[TilikCloudKitSchema.Field.email] as? String != email {
                    record[TilikCloudKitSchema.Field.email] = email as CKRecordValue
                    _ = try await db.save(record)
                }
            } catch { CollaborationDiagnostics.failure("officer_identity_publish_failed", error: error) }
        }
        let id = officerRecordID("officer-profile-", participantID: participantID, workspace: workspace)
        guard let record = try? await db.record(for: id),
              record[TilikCloudKitSchema.Field.participantID] as? String == participantID else { return (nil, email) }
        if let userID = participant.userIdentity.userRecordID,
           (record.creatorUserRecordID != userID || record.lastModifiedUserRecordID != userID) { return (nil, email) }
        return (record[TilikCloudKitSchema.Field.name] as? String,
                email ?? (record[TilikCloudKitSchema.Field.email] as? String))
    }
}
#endif
