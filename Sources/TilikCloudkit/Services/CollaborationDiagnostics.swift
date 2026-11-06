//
//  CollaborationDiagnostics.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation
import OSLog

/// Log only operation IDs and error codes, never locations or invitation URLs.
public enum CollaborationDiagnostics {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Tilik", category: "Collaboration")

    public static func record(_ name: String, operation: String = "") {
        logger.info("\(name, privacy: .public) operation=\(operation, privacy: .private)")
    }

    public static func failure(_ name: String, error: Error, operation: String = "", retryAfter: TimeInterval? = nil) {
        let error = error as NSError
        logger.error(
            "\(name, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code) retry_after=\(retryAfter ?? 0, privacy: .public) operation=\(operation, privacy: .private)"
        )
    }
}
