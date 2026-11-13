import Foundation
import Testing
@testable import TilikCloudkit

struct OfficerAssignmentTests {
    @Test func legacyResponsesPreserveDetectionAndRejectAlteredData() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let point = OfficerAssignment.Point(id: "p", name: "Asap", latitude: 1, longitude: 104, temperatureC: 48, isFire: false, detectionType: "smoke")
        let oldPoint = OfficerAssignment.Point(id: "p", name: "Asap", latitude: 1, longitude: 104, temperatureC: 48, isFire: false)
        func task(_ p: OfficerAssignment.Point) -> OfficerAssignment {
            OfficerAssignment(id: "t", workspaceID: "w", recipientID: "a", zoneID: "z", subzoneID: "a1", subzoneName: "A1", scope: .hotspot, points: [p], sentAt: now, deadline: now, isSimulation: true)
        }
        let original = task(point)
        #expect(point.isCritical && point.kind == "smoke")
        #expect(original.matchesLegacyResponse(task(oldPoint)))
        #expect(!original.matchesLegacyResponse(task(.init(id: "p", name: "Asap", latitude: 2, longitude: 104, temperatureC: 48, isFire: false))))
        var legacy = task(oldPoint); legacy.status = .rejected; legacy.rejectionReason = "Tidak tersedia"
        let events = [CollaborationEvent(id: "t", workspaceID: "w", kind: .assignment, senderID: "owner", senderRole: .operatorRole, assignment: original),
                      CollaborationEvent(workspaceID: "w", kind: .assignmentResponse, senderID: "a", senderRole: .officer, assignment: legacy)]
        let projected = try #require(OfficerAssignmentProjector.current(events).first)
        #expect(projected.status == .rejected && projected.points.first?.kind == "smoke")
        #expect(try JSONDecoder().decode(OfficerAssignment.self, from: JSONEncoder().encode(task(oldPoint))) == task(oldPoint))
    }
    @Test func connectionEventAndLegacyEventRoundTrip() throws {
        let connected = CollaborationEvent(id: "member-connected-a", workspaceID: "w", kind: .memberConnected,
                                           senderID: "owner", senderRole: .operatorRole, memberID: "a")
        let encoded = try JSONEncoder().encode(connected)
        #expect(try JSONDecoder().decode(CollaborationEvent.self, from: encoded) == connected)
        let legacy = CollaborationEvent(id: "old", workspaceID: "w", kind: .ping, senderID: "owner", senderRole: .operatorRole)
        let legacyData = try JSONEncoder().encode(legacy)
        #expect(try JSONDecoder().decode(CollaborationEvent.self, from: legacyData).memberID == nil)
    }
    @Test func subzoneAndSinglePointRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<10).map { index in
            OfficerAssignment.Point(id: "point-\(index)", name: "Api \(index)", latitude: 1, longitude: 104,
                                    temperatureC: 70, isFire: true)
        }
        let task = OfficerAssignment(id: "task", workspaceID: "workspace", recipientID: "officer-a",
                                     zoneID: "zone", subzoneID: "a1", subzoneName: "A1", scope: .subzone,
                                     points: points, sentAt: now, deadline: now.addingTimeInterval(1800), isSimulation: true)
        #expect(task.isValid)
        #expect(try JSONDecoder().decode(OfficerAssignment.self, from: JSONEncoder().encode(task)) == task)
        let invalid = OfficerAssignment(id: "task2", workspaceID: "workspace", recipientID: "officer-b",
                                        zoneID: "zone", subzoneID: "a1", subzoneName: "A1", scope: .hotspot,
                                        points: points, sentAt: now, deadline: now.addingTimeInterval(1800), isSimulation: true)
        #expect(!invalid.isValid)
    }

    @Test func responsesAreIndependentPerOfficer() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<10).map { OfficerAssignment.Point(id: "point-\($0)", name: "Api \($0)", latitude: 1,
            longitude: 104, temperatureC: 70, isFire: true) }
        let tasks = ["a", "b", "c", "d"].map { officer in
            OfficerAssignment(id: "task-\(officer)", workspaceID: "workspace", recipientID: officer,
                zoneID: "zone", subzoneID: "a1", subzoneName: "A1", scope: .subzone, points: points,
                sentAt: now, deadline: now.addingTimeInterval(1800), isSimulation: true)
        }
        var events = tasks.map { task in CollaborationEvent(id: task.id, workspaceID: "workspace", kind: .assignment,
            senderID: "operator", senderRole: .operatorRole, assignment: task, clientCreatedAt: now) }
        var reply = tasks[0]; reply.status = .accepted; reply.respondedAt = now.addingTimeInterval(3)
        events.append(CollaborationEvent(id: "response", workspaceID: "workspace", kind: .assignmentResponse,
            senderID: "officer-a", senderRole: .officer, assignment: reply, clientCreatedAt: now.addingTimeInterval(3)))
        let report = InspectionReport(note: "Sudah disiram", hasPhoto: false, photoSHA256: nil)
        events.append(CollaborationEvent(id: "point-report", workspaceID: "workspace", kind: .assignmentResponse,
            senderID: "officer-a", senderRole: .officer, hotspotID: "point-0", inspectionReport: report,
            assignment: reply, clientCreatedAt: now.addingTimeInterval(4)))
        #expect(OfficerAssignmentProjector.current(events, recipientID: "a").first?.status == .accepted)
        #expect(OfficerAssignmentProjector.current(events, recipientID: "b").first?.status == .pending)
        #expect(OfficerAssignmentProjector.current(events, recipientID: "a").first?.points.count == 10)
        #expect(OfficerAssignmentProjector.current(events, recipientID: "unknown").isEmpty)
    }
}
