#if os(iOS)
//
//  CloudKitCollaborationService+Records.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation
import CloudKit

extension CloudKitCollaborationService {
    /// Zone change sync fetches only lightweight payload keys; fetch evidence on demand.
    public func fetchHazardEvidenceURL(eventID: String, context: WorkspaceContext) async throws -> URL {
        let record = try await database(context.scope).record(
            for: CKRecord.ID(recordName: eventID, zoneID: zoneID(context)))
        guard record.recordType == TilikCloudKitSchema.RecordType.hotspot,
              record[TilikCloudKitSchema.Field.workspaceID] as? String == context.workspaceID,
              try decodeEvent(record).hazard != nil else { throw CollaborationError.targetUnavailable }
        return try evidence.fetchedEvidenceURL(record: record, eventID: eventID)
    }

    public func fetchRGBHotspotImageURL(eventID: String, context: WorkspaceContext) async throws -> URL {
        let record = try await database(context.scope).record(
            for: CKRecord.ID(recordName: eventID, zoneID: zoneID(context)))
        guard record.recordType == TilikCloudKitSchema.RecordType.hotspot,
              record[TilikCloudKitSchema.Field.workspaceID] as? String == context.workspaceID,
              let source = (record[TilikCloudKitSchema.Field.rgbImage] as? CKAsset)?.fileURL
        else { throw CollaborationError.targetUnavailable }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TilikRGBReceived/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("rgb.jpg")
        do { try FileManager.default.copyItem(at: source, to: target); return target }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    public func fetchHotspotImageURLs(eventID: String, context: WorkspaceContext) async throws -> [URL] {
        let record = try await database(context.scope).record(
            for: CKRecord.ID(recordName: eventID, zoneID: zoneID(context)))
        guard record.recordType == TilikCloudKitSchema.RecordType.hotspot,
              record[TilikCloudKitSchema.Field.workspaceID] as? String == context.workspaceID,
              record[TilikCloudKitSchema.Field.thermalImage] is CKAsset,
              record[TilikCloudKitSchema.Field.rgbImage] is CKAsset else { throw CollaborationError.targetUnavailable }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("TilikQAReceived/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let fields = [(TilikCloudKitSchema.Field.thermalImage, "thermal.png"), (TilikCloudKitSchema.Field.rgbImage, "rgb.jpg")]
            let files = try fields.map { field, name -> URL in
                guard let source = (record[field] as? CKAsset)?.fileURL else {
                    throw CollaborationError.targetUnavailable
                }
                let target = destination.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: target)
                return target
            }
            return files
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Downloads the Petugas' check photo of an observed response (opened on demand).
    public func fetchInspectionPhotoData(responseID: String, context: WorkspaceContext) async throws -> Data {
        let record = try await database(context.scope).record(
            for: CKRecord.ID(recordName: responseID, zoneID: zoneID(context)))
        guard [TilikCloudKitSchema.RecordType.response, TilikCloudKitSchema.RecordType.assignmentResponse].contains(record.recordType),
              record[TilikCloudKitSchema.Field.workspaceID] as? String == context.workspaceID,
              let url = (record[TilikCloudKitSchema.Field.inspectionPhoto] as? CKAsset)?.fileURL
        else { throw CollaborationError.targetUnavailable }
        // Read now: CloudKit may clean its staging file at any time.
        return try Data(contentsOf: url)
    }

    public func encode(_ event: CollaborationEvent, context: WorkspaceContext) throws -> CKRecord {
        let types: [CollaborationEvent.Kind: String] = [
            .hotspot: TilikCloudKitSchema.RecordType.hotspot, .ping: TilikCloudKitSchema.RecordType.ping, .observed: TilikCloudKitSchema.RecordType.response,
            .subzoneRun: TilikCloudKitSchema.RecordType.subzoneRun,
            .assignment: TilikCloudKitSchema.RecordType.assignment,
            .assignmentResponse: TilikCloudKitSchema.RecordType.assignmentResponse,
            .memberConnected: TilikCloudKitSchema.RecordType.memberConnected
        ]
        guard let recordType = types[event.kind] else { throw CollaborationError.conflictingEvent }
        let record = CKRecord(
            recordType: recordType, recordID: CKRecord.ID(recordName: event.id, zoneID: zoneID(context)))
        record[TilikCloudKitSchema.Field.workspaceID] = event.workspaceID as CKRecordValue
        record[TilikCloudKitSchema.Field.payload] = try JSONEncoder().encode(event) as CKRecordValue
        evidence.encodeEvidence(record: record, event: event)
        return record
    }

    public func decodeEvent(_ record: CKRecord) throws -> CollaborationEvent {
        guard [TilikCloudKitSchema.RecordType.hotspot, TilikCloudKitSchema.RecordType.ping, TilikCloudKitSchema.RecordType.response, TilikCloudKitSchema.RecordType.subzoneRun, TilikCloudKitSchema.RecordType.assignment, TilikCloudKitSchema.RecordType.assignmentResponse, TilikCloudKitSchema.RecordType.memberConnected].contains(record.recordType),
            let data = record[TilikCloudKitSchema.Field.payload] as? Data
        else { throw CollaborationError.invalidWorkspace }
        var event = try JSONDecoder().decode(CollaborationEvent.self, from: data)
        guard event.id == record.recordID.recordName,
            event.workspaceID == record[TilikCloudKitSchema.Field.workspaceID] as? String
        else { throw CollaborationError.invalidWorkspace }
        event.serverCreatedAt = record.creationDate
        evidence.decodeEvidence(record: record, event: event)
        return event
    }

    public func decodeWorkspace(_ record: CKRecord, scope: WorkspaceContext.Scope) throws -> TPAWorkspace {
        guard record.recordType == TilikCloudKitSchema.RecordType.workspace, let identifier = record[TilikCloudKitSchema.Field.workspaceID] as? String,
            let name = record[TilikCloudKitSchema.Field.name] as? String, let owner = record[TilikCloudKitSchema.Field.ownerAccountID] as? String,
            (record[TilikCloudKitSchema.Field.schemaVersion] as? NSNumber)?.intValue == 1
        else { throw CollaborationError.invalidWorkspace }
        let zone = record.recordID.zoneID
        return TPAWorkspace(
            context: WorkspaceContext(
                container: containerIdentifier, scope: scope, zoneName: zone.zoneName,
                zoneOwner: zone.ownerName, workspaceID: identifier
            ), name: name, ownerAccountID: owner, schemaVersion: 1
        )
    }

    public func archive(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    public func unarchive(_ token: Data?) throws -> CKServerChangeToken? {
        guard let token else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: token)
    }
}

#endif
