//
//  CollaborationAlertServing.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

@MainActor
public protocol CollaborationAlertServing {
    func requestPermission() async throws -> Bool
    /// Returns false when alerts are intentionally suppressed by system permission.
    func schedule(id: String, body: String) async throws -> Bool
    func cancelPending()
}
