import Foundation

extension CollaborationPolicy {
    public static func alertBody(for event: CollaborationEvent, scope: WorkspaceContext.Scope) -> String? {
        if event.hazard?.notifyRecipient == false { return nil }
        switch (event.kind, scope, event.senderRole) {
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
