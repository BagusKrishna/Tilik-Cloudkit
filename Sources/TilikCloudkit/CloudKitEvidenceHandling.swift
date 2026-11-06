#if os(iOS)
import Foundation
import CloudKit

/// Supplies app-specific evidence persistence without embedding AI inference in CloudKit.
@MainActor
public protocol CloudKitEvidenceHandling {
    func fetchedEvidenceURL(record: CKRecord, eventID: String) throws -> URL
    func encodeEvidence(record: CKRecord, event: CollaborationEvent)
    func decodeEvidence(record: CKRecord, event: CollaborationEvent)
}

#endif
