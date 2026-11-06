//
//  CollaborationPolicy.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Pure validation rules shared by presentation, sync, and tests.
public enum CollaborationPolicy {
    /// Accepts a single decimal comma or point, never grouping or mixed separators.
    public static func coordinate(_ text: String, latitude: Bool) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[+-]?[0-9]+([.,][0-9]+)?$"#, options: .regularExpression) != nil,
            let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite
        else { return nil }
        return (latitude ? -90...90 : -180...180).contains(number) ? number : nil
    }

    public static func invitationURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https", url.host?.lowercased() == "www.icloud.com",
            url.path.hasPrefix("/share/"), url.path.count > "/share/".count,
            url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        return url
    }

    public static func canJoin(existing: [TPAWorkspace], requestedZone: String, owner: String) -> Bool {
        let memberships = existing.filter { $0.context.scope == .participant }
        return memberships.isEmpty
            || memberships.allSatisfy {
                $0.context.zoneName == requestedZone && $0.context.zoneOwner == owner
            }
    }

    /// Hotspots still current: an escalated hazard replaces its earlier event on the map and list.
    public static func currentHotspots(_ events: [CollaborationEvent]) -> [CollaborationEvent] {
        let hotspots = events.filter { $0.kind == .hotspot }
        let superseded = Set(hotspots.compactMap { $0.hazard?.supersedesEventID })
        return hotspots.filter { !superseded.contains($0.id) }
    }

    public static func observed(_ hotspotID: String, in events: [CollaborationEvent]) -> Bool {
        let latest = events.filter { $0.kind == .observed && $0.hotspotID == hotspotID }.max {
            ($0.serverCreatedAt ?? $0.clientCreatedAt, $0.id)
                < ($1.serverCreatedAt ?? $1.clientCreatedAt, $1.id)
        }
        return latest.map { ($0.status ?? .observed) == .observed } ?? false
    }

    /// Newest observed response for a hot spot that carries a Petugas report.
    public static func latestInspection(_ hotspotID: String, in events: [CollaborationEvent]) -> CollaborationEvent? {
        events.filter {
            $0.kind == .observed && $0.hotspotID == hotspotID
                && ($0.status ?? .observed) == .observed && $0.inspectionReport != nil
        }.max {
            ($0.serverCreatedAt ?? $0.clientCreatedAt, $0.id)
                < ($1.serverCreatedAt ?? $1.clientCreatedAt, $1.id)
        }
    }

    public static func alertKey(event: CollaborationEvent, workspaceKey: String) -> String {
        // Keep legacy keys so upgrading never replays previously handled observed alerts.
        let logicalID =
            event.kind == .observed && event.status == nil
            ? "observed:\(event.hotspotID ?? event.id)" : event.id
        return "\(workspaceKey)|\(logicalID)"
    }


}

/// Derives current and historical subzone scans without mutating CloudKit records.
/// Legacy hotspots without a frozen subzone remain current until explicitly migrated.
public struct SubzoneRunProjector {
    public struct CompletedRun {
        public let marker: CollaborationEvent
        public let details: CollaborationSubzoneRun
        public let hotspots: [CollaborationEvent]

        public var key: String {
            [marker.workspaceID, details.zoneID, details.subzoneID].joined(separator: "|")
        }
    }

    public static func completedRuns(_ events: [CollaborationEvent]) -> [CompletedRun] {
        events.compactMap { marker in
            guard marker.kind == .subzoneRun, let run = marker.subzoneRun,
                  run.hotspotCount >= 0, !run.subzoneID.isEmpty,
                  run.sourceMode == "rgbAndThermal" else { return nil }
            let hotspots = events.filter { event in
                guard event.kind == .hotspot, event.workspaceID == marker.workspaceID,
                      let details = event.hotspotDetails else { return false }
                return details.sessionID == run.sessionID && details.zoneID == run.zoneID
                    && details.subzoneID == run.subzoneID
            }
            let ids = Set(hotspots.map(\.id))
            guard ids.count == run.hotspotCount,
                  CollaborationSubzoneRun.digest(Array(ids)) == run.eventIDsDigest else { return nil }
            return CompletedRun(marker: marker, details: run, hotspots: hotspots)
        }
    }

    public static func activeRuns(_ events: [CollaborationEvent]) -> [CompletedRun] {
        let grouped = Dictionary(grouping: completedRuns(events), by: \.key)
        return grouped.values.compactMap { $0.max(by: older) }
    }

    public static func historicalRuns(_ events: [CollaborationEvent]) -> [CompletedRun] {
        let grouped = Dictionary(grouping: completedRuns(events), by: \.key)
        return grouped.values.flatMap { group -> [CompletedRun] in
            guard let newest = group.max(by: older) else { return [] }
            return group.filter { $0.marker.id != newest.marker.id }
        }.sorted { older($1, $0) }
    }

    public static func activeHotspots(_ events: [CollaborationEvent]) -> [CollaborationEvent] {
        let legacy = events.filter { $0.kind == .hotspot && $0.hotspotDetails?.subzoneID == nil }
        return legacy + activeRuns(events).flatMap(\.hotspots)
    }

    private static func older(_ lhs: CompletedRun, _ rhs: CompletedRun) -> Bool {
        // Offline uploads can reach CloudKit out of order; flight completion owns chronology.
        (lhs.details.completedAt, lhs.marker.id) < (rhs.details.completedAt, rhs.marker.id)
    }
}
