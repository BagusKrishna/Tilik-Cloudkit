//
//  WorkspaceContext.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Identifies a workspace independently of its display name.
public struct WorkspaceContext: Codable, Equatable, Hashable, Sendable {
    public enum Scope: String, Codable, Sendable { case owner, participant }

    public let container: String
    public let scope: Scope
    public let zoneName: String
    public let zoneOwner: String
    public let workspaceID: String

    public init(container: String, scope: Scope, zoneName: String, zoneOwner: String, workspaceID: String) {
        self.container = container
        self.scope = scope
        self.zoneName = zoneName
        self.zoneOwner = zoneOwner
        self.workspaceID = workspaceID
    }

    public var key: String { [container, scope.rawValue, zoneOwner, zoneName, workspaceID].joined(separator: "|") }

    public static func scope(from key: String) -> Scope? {
        let components = key.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 5 else { return nil }
        return Scope(rawValue: String(components[1]))
    }
}
