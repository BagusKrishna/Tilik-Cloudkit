//
//  TPAWorkspace.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// A landfill workspace and its server ownership identity.
public struct TPAWorkspace: Identifiable, Codable, Equatable, Sendable {
    public let context: WorkspaceContext
    public let name: String
    public let ownerAccountID: String
    public let schemaVersion: Int
    public init(context: WorkspaceContext, name: String, ownerAccountID: String, schemaVersion: Int) {
        self.context = context
        self.name = name
        self.ownerAccountID = ownerAccountID
        self.schemaVersion = schemaVersion
    }

    public var id: String { context.key }
}
