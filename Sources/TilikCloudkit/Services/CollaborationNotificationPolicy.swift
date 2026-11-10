import Foundation

extension CollaborationPolicy {
    public static func alertBody(for event: CollaborationEvent, scope: WorkspaceContext.Scope) -> String? {
        if event.hazard?.notifyRecipient == false { return nil }
        switch (event.kind, scope, event.senderRole) {
        case (.assignment, .participant, .operatorRole):
            guard let task = event.assignment else { return nil }
            return "Tugas baru: \(task.subzoneName)"
        case (.assignmentResponse, .owner, .officer):
            guard let task = event.assignment else { return nil }
            if event.inspectionReport != nil {
                let point = task.points.first { $0.id == event.hotspotID }?.name ?? task.subzoneName
                return "Laporan \(point) tersedia"
            }
            switch task.status {
            case .accepted: return "Tugas \(task.subzoneName) diterima"
            case .rejected: return "Tugas \(task.subzoneName) ditolak"
            case .completed: return "Tugas \(task.subzoneName) selesai"
            case .pending: return nil
            }
        case (.hotspot, .participant, _):
            guard let hazard = event.hazard else { return "Hotspot terdeteksi, segera cek" }
            return "\(hazard.level.alertTitle). "
                + hazard.level.alertMessage(subzoneLabel: hazard.subzoneLabel, zoneName: hazard.zoneName)
        case (.ping, .participant, .operatorRole), (.ping, .owner, .officer): return "Ping"
        case (.observed, .owner, _), (.observed, .participant, _):
            if event.status == nil && scope == .participant { return nil }
            return event.status == .unobserved
                ? "Hotspot perlu dipantau kembali" : "Hotspot sudah terpantau"
        default: return nil
        }
    }
}
