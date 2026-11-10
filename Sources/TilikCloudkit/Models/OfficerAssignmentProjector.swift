import Foundation

public enum OfficerAssignmentProjector {
    public static func current(_ events: [CollaborationEvent], recipientID: String? = nil) -> [OfficerAssignment] {
        let originals = events.filter { $0.kind == .assignment && $0.senderRole == .operatorRole }
        return originals.compactMap { original in
            guard var task = original.assignment, task.isValid, task.status == .pending, task.id == original.id,
                  recipientID == nil || task.recipientID == recipientID else { return nil }
            let responses = events.filter {
                guard $0.kind == .assignmentResponse, $0.senderRole == .officer,
                      var response = $0.assignment, response.isValid,
                      response.status == .accepted || response.status == .rejected || response.status == .completed else { return false }
                response.status = .pending
                response.respondedAt = nil
                response.rejectionReason = nil
                return response == task
            }
            if let response = responses.max(by: { ($0.serverCreatedAt ?? $0.clientCreatedAt, $0.id) < ($1.serverCreatedAt ?? $1.clientCreatedAt, $1.id) }),
               let value = response.assignment, value.isValid {
                task.status = value.status; task.respondedAt = value.respondedAt; task.rejectionReason = value.rejectionReason
            }
            return task
        }.sorted { $0.sentAt > $1.sentAt }
    }
}
