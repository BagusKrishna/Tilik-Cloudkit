//
//  CollaborationEvent.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import CryptoKit
import Foundation

/// A completion marker for one verified sortie and one frozen subzone.
/// Hotspots may arrive first, but neither client promotes this run until all IDs match.
public struct CollaborationSubzoneRun: Codable, Equatable, Sendable {
    public let sessionID: String
    public let zoneID: String
    public let zoneName: String
    public let subzoneID: String
    public let subzoneName: String
    public let sourceMode: String
    public let startedAt: Date?
    public let completedAt: Date
    public let hotspotCount: Int
    public let eventIDsDigest: String

    public init(sessionID: String, zoneID: String, zoneName: String, subzoneID: String, subzoneName: String, sourceMode: String, startedAt: Date?, completedAt: Date, hotspotCount: Int, eventIDsDigest: String) {
        self.sessionID = sessionID; self.zoneID = zoneID; self.zoneName = zoneName
        self.subzoneID = subzoneID; self.subzoneName = subzoneName; self.sourceMode = sourceMode
        self.startedAt = startedAt; self.completedAt = completedAt; self.hotspotCount = hotspotCount; self.eventIDsDigest = eventIDsDigest
    }

    public static func digest(_ ids: [String]) -> String {
        let bytes = Data(ids.sorted().joined(separator: "\n").utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Immutable collaboration events use stable IDs across retries and devices.
public struct CollaborationEvent: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case hotspot, ping, observed, subzoneRun, assignment, assignmentResponse, memberConnected }
    public enum InspectionStatus: String, Codable, Sendable {
        case observed, unobserved
        public var title: String { self == .observed ? "Sudah Dipantau" : "Belum Dipantau" }
    }

    public enum Role: String, Codable, Sendable { case operatorRole, officer }

    /// Smoke or fire confirmed by the operator's live detector and sent without operator action.
    /// Optional, so payloads without it (manual hotspots, older app versions) still decode.
    public struct HazardReport: Codable, Equatable, Sendable {
        public let incidentID: String
        public let level: HazardLevel
        public let peakConfidence: Double
        public let missionID: String
        public let zoneName: String
        public let subzoneLabel: String?
        public let detectedAt: Date
        /// `aircraftPosition`: latitude/longitude are the drone's GPS position at confirmation, not
        /// the hazard's ground position. `unavailable`: no fresh GPS fix, so no coordinates.
        public let locationBasis: String
        /// The earlier hotspot event of the same incident, replaced by this escalation.
        public let supersedesEventID: String?
        /// Evidence image relative to the sender's `HazardEvidenceStore`; uploaded as a CKAsset.
        public let evidencePath: String?
        /// Missing in legacy payloads means alert, preserving existing clients.
        public var notifyRecipient: Bool? = nil
        /// Synthetic / injected frames must never be sent to a real workspace.
        public var isTestInput: Bool? = nil

        public init(incidentID: String, level: HazardLevel, peakConfidence: Double, missionID: String, zoneName: String, subzoneLabel: String?, detectedAt: Date, locationBasis: String, supersedesEventID: String?, evidencePath: String?, notifyRecipient: Bool? = nil, isTestInput: Bool? = nil) {
            self.incidentID = incidentID; self.level = level; self.peakConfidence = peakConfidence
            self.missionID = missionID; self.zoneName = zoneName; self.subzoneLabel = subzoneLabel
            self.detectedAt = detectedAt; self.locationBasis = locationBasis; self.supersedesEventID = supersedesEventID
            self.evidencePath = evidencePath; self.notifyRecipient = notifyRecipient; self.isTestInput = isTestInput
        }
    }

    public let id: String
    public let workspaceID: String
    public let kind: Kind
    public let clientCreatedAt: Date
    public let senderID: String
    public let senderRole: Role
    public let latitude: Double?
    public let longitude: Double?
    public let hotspotID: String?
    // Missing on legacy observed responses; optional preserves old payloads and outbox intents.
    public let status: InspectionStatus?
    public let hotspotDetails: CollaborationHotspotDetails?
    /// Petugas' photo + note for an observed response. nil on older payloads.
    public let inspectionReport: InspectionReport?
    public let hazard: HazardReport?
    /// A marker written only after every verified hotspot in this subzone run is acknowledged.
    public let subzoneRun: CollaborationSubzoneRun?
    public let assignment: OfficerAssignment?
    public let memberID: String?
    public var serverCreatedAt: Date?

    public init(
        id: String = UUID().uuidString,
        workspaceID: String,
        kind: Kind,
        senderID: String,
        senderRole: Role,
        latitude: Double? = nil,
        longitude: Double? = nil,
        hotspotID: String? = nil,
        status: InspectionStatus? = nil,
        hotspotDetails: CollaborationHotspotDetails? = nil,
        inspectionReport: InspectionReport? = nil,
        hazard: HazardReport? = nil,
        subzoneRun: CollaborationSubzoneRun? = nil,
        assignment: OfficerAssignment? = nil,
        memberID: String? = nil,
        clientCreatedAt: Date = Date()
    ) {
        self.inspectionReport = inspectionReport
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.clientCreatedAt = clientCreatedAt
        self.senderID = senderID
        self.senderRole = senderRole
        self.latitude = latitude
        self.longitude = longitude
        self.hotspotID = hotspotID
        self.status = status
        self.hotspotDetails = hotspotDetails
        self.hazard = hazard
        self.subzoneRun = subzoneRun
        self.assignment = assignment
        self.memberID = memberID
    }

    /// Server timestamps do not change the identity of an already accepted intent.
    public func representsSameIntent(as other: Self) -> Bool {
        var lhs = self
        var rhs = other
        lhs.serverCreatedAt = nil
        rhs.serverCreatedAt = nil
        return lhs == rhs
    }

    /// Allows an owner to fill the temperature omitted from an earlier thermal import.
    /// All other event and hotspot fields must still describe the same observation.
    public func repairsMissingThermalTemperature(in previous: Self) -> Bool {
        guard kind == .hotspot, previous.kind == .hotspot,
              let new = hotspotDetails, let old = previous.hotspotDetails,
              old.source == .thermal, old.peakTemperatureC == nil,
              old.temperatureQuality == .missing,
              let value = new.peakTemperatureC, value.isFinite,
              new.temperatureQuality != .missing,
              new.riskLevel == .classify(temperatureC: value, quality: new.temperatureQuality)
        else { return false }

        let correctedDetails = CollaborationHotspotDetails(
            version: old.version, sourceKey: old.sourceKey, displayNumber: old.displayNumber,
            sessionID: old.sessionID, zoneID: old.zoneID, zoneName: old.zoneName,
            subzoneID: old.subzoneID, subzoneName: old.subzoneName,
            source: old.source, detectionType: old.detectionType,
            capturedAt: old.capturedAt, captureTimeText: old.captureTimeText,
            peakTemperatureC: value, temperatureQuality: new.temperatureQuality,
            riskLevel: new.riskLevel)
        guard correctedDetails == new else { return false }

        let correctedEvent = CollaborationEvent(
            id: previous.id, workspaceID: previous.workspaceID, kind: previous.kind,
            senderID: previous.senderID, senderRole: previous.senderRole,
            latitude: previous.latitude, longitude: previous.longitude,
            hotspotID: previous.hotspotID, status: previous.status,
            hotspotDetails: correctedDetails, clientCreatedAt: previous.clientCreatedAt)
        return representsSameIntent(as: correctedEvent)
    }
}
