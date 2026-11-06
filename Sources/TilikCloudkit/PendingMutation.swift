//
//  PendingMutation.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Durable intent; failed and uncertain writes keep their original event ID.
public struct PendingMutation: Identifiable, Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case queued, sending, failed, needsReview }

    public let accountID: String
    public let context: WorkspaceContext
    public let event: CollaborationEvent
    /// Durable local copies used only by image-backed thermal hotspots.
    public var attachments: HotspotAttachmentPaths?
    /// Postflight RGB detection image, when no thermal capture belongs to the same event.
    public var rgbJPEGPath: String? = nil
    /// Durable local JPEG for an observed response with an inspection photo.
    public var inspectionPhotoPath: String?
    public var state: State = .queued
    public var attempts = 0
    public var retryAt: Date?
    public var errorMessage: String?
    public init(accountID: String, context: WorkspaceContext, event: CollaborationEvent, attachments: HotspotAttachmentPaths? = nil, rgbJPEGPath: String? = nil, inspectionPhotoPath: String? = nil, state: State = .queued, attempts: Int = 0, retryAt: Date? = nil, errorMessage: String? = nil) {
        self.accountID = accountID; self.context = context; self.event = event; self.attachments = attachments
        self.rgbJPEGPath = rgbJPEGPath; self.inspectionPhotoPath = inspectionPhotoPath; self.state = state
        self.attempts = attempts; self.retryAt = retryAt; self.errorMessage = errorMessage
    }

    public var id: String { event.id }
}

public struct HotspotAttachmentPaths: Codable, Equatable, Sendable {
    public let thermalPNG: String
    public let rgbJPEG: String

    public init(thermalPNG: String, rgbJPEG: String) { self.thermalPNG = thermalPNG; self.rgbJPEG = rgbJPEG }

    public var urls: [URL] { [URL(fileURLWithPath: thermalPNG), URL(fileURLWithPath: rgbJPEG)] }
}
