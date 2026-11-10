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

        public init(id: String, name: String, latitude: Double, longitude: Double, temperatureC: Double?, isFire: Bool) {
            self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
            self.temperatureC = temperatureC; self.isFire = isFire
        }
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
}
