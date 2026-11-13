import Foundation

/// A separate task per recipient keeps each officer's response independent.
public struct OfficerAssignment: Codable, Equatable, Identifiable, Sendable {
    public enum Scope: String, Codable, Sendable { case subzone, hotspot }
    public enum Status: String, Codable, Sendable { case pending, accepted, rejected, completed }

    public struct Point: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let latitude: Double
        public let longitude: Double
        public let temperatureC: Double?
        public let isFire: Bool
        /// Optional for records written by older app versions. Unknown values remain readable.
        public let detectionType: String?

        public init(id: String, name: String, latitude: Double, longitude: Double, temperatureC: Double?, isFire: Bool, detectionType: String? = nil) {
            self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
            self.temperatureC = temperatureC; self.isFire = isFire; self.detectionType = detectionType
        }

        public var kind: String {
            switch detectionType {
            case let value? where ["fire", "smoke", "smokeAndFire", "heat"].contains(value): return value
            default: return isFire ? "fire" : "heat"
            }
        }
        public var isCritical: Bool { kind == "fire" || kind == "smoke" || kind == "smokeAndFire" }
    }

    public let id: String
    public let workspaceID: String
    public let recipientID: String
    public let zoneID: String
    public let subzoneID: String
    public let subzoneName: String
    public let scope: Scope
    public let points: [Point]
    public let sentAt: Date
    public let deadline: Date
    public let isSimulation: Bool
    public var status: Status
    public var respondedAt: Date?
    public var rejectionReason: String?

    public init(id: String, workspaceID: String, recipientID: String, zoneID: String, subzoneID: String,
                subzoneName: String, scope: Scope, points: [Point], sentAt: Date, deadline: Date,
                isSimulation: Bool, status: Status = .pending, respondedAt: Date? = nil, rejectionReason: String? = nil) {
        self.id = id; self.workspaceID = workspaceID; self.recipientID = recipientID
        self.zoneID = zoneID; self.subzoneID = subzoneID; self.subzoneName = subzoneName
        self.scope = scope; self.points = points; self.sentAt = sentAt; self.deadline = deadline
        self.isSimulation = isSimulation; self.status = status; self.respondedAt = respondedAt
        self.rejectionReason = rejectionReason
    }

    public var isValid: Bool {
        !id.isEmpty && !workspaceID.isEmpty && !recipientID.isEmpty && !subzoneID.isEmpty
            && !points.isEmpty && (scope != .hotspot || points.count == 1)
            && deadline >= sentAt
            && points.allSatisfy { !$0.id.isEmpty && $0.latitude.isFinite && (-90...90).contains($0.latitude)
                && $0.longitude.isFinite && (-180...180).contains($0.longitude)
                && ($0.temperatureC?.isFinite ?? true) }
    }

    /// Older clients drop detectionType when responding; all original fields still must match.
    public func matchesLegacyResponse(_ response: OfficerAssignment) -> Bool {
        guard id == response.id, workspaceID == response.workspaceID, recipientID == response.recipientID,
              zoneID == response.zoneID, subzoneID == response.subzoneID, subzoneName == response.subzoneName,
              scope == response.scope, sentAt == response.sentAt, deadline == response.deadline,
              isSimulation == response.isSimulation, status == response.status,
              respondedAt == response.respondedAt, rejectionReason == response.rejectionReason,
              points.count == response.points.count else { return false }
        return zip(points, response.points).allSatisfy { original, answer in
            original.id == answer.id && original.name == answer.name && original.latitude == answer.latitude &&
            original.longitude == answer.longitude && original.temperatureC == answer.temperatureC &&
            original.isFire == answer.isFire && (answer.detectionType == nil || original.detectionType == answer.detectionType)
        }
    }
}
