//
//  InspectionReport.swift
//  Tilik
//
//  Created by Amalia Sandi Alzahrah on 28/10/26.
//

import Foundation

/// Petugas' check result for one hot spot. Lives in the `payload` of a
/// `TilikResponse` (observed) record; the photo itself is the optional
/// `inspectionPhoto` CKAsset on the same record. Optional everywhere, so older
/// responses without a report still decode and still mean "Sudah di Cek".
public struct InspectionReport: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumNoteLength = 500

    public let version: Int
    /// Keterangan from the Update Pengecekan sheet (may be empty).
    public let note: String
    /// When the photo was taken (or the report was written if there is no photo).
    public let capturedAt: Date
    /// True when an `inspectionPhoto` asset belongs to this report.
    public let hasPhoto: Bool
    /// SHA-256 of the uploaded JPEG, used to verify retries and downloads.
    public let photoSHA256: String?
    /// Where the Petugas stood when reporting (optional).
    public let latitude: Double?
    public let longitude: Double?

    public init(
        note: String, capturedAt: Date = Date(), hasPhoto: Bool, photoSHA256: String?,
        latitude: Double? = nil, longitude: Double? = nil
    ) {
        self.version = Self.currentVersion
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNoteLength))
        self.capturedAt = capturedAt
        self.hasPhoto = hasPhoto
        self.photoSHA256 = photoSHA256
        self.latitude = latitude.flatMap { $0.isFinite ? $0 : nil }
        self.longitude = longitude.flatMap { $0.isFinite ? $0 : nil }
    }
}
