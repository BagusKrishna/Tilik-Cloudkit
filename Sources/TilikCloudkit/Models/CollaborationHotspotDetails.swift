//
//  CollaborationHotspotDetails.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 27/10/26.
//

import Foundation

/// CloudKit payload risk. Kept separate from the existing Pantauan UI risk type.
public enum HotspotCloudRiskLevel: String, Codable, Sendable, CaseIterable {
    case critical, emergency, warning, safe, unknown

    public var title: String {
        switch self {
        case .critical: return "Berbahaya"
        case .emergency: return "Darurat"
        case .warning: return "Waspada"
        case .safe: return "Aman"
        case .unknown: return "Belum dinilai"
        }
    }

    public var priority: Int {
        switch self {
        case .critical: return 0
        case .emergency: return 1
        case .warning: return 2
        case .safe: return 3
        case .unknown: return 4
        }
    }

    public var titleIndonesian: String { title }

    public static func classify(temperatureC: Double?, quality: CollaborationHotspotDetails.TemperatureQuality = .calibrated) -> Self {
        guard let temperatureC, temperatureC.isFinite else { return .unknown }
        switch temperatureC {
        case 70...: return .critical
        case 50..<70: return .emergency
        case 40..<50: return .warning
        default: return .safe
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

/// Immutable observation details inside the existing event JSON payload.
public struct CollaborationHotspotDetails: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case rgb, thermal
        /// Retains coordinates from future payloads without attributing them to the wrong sensor.
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .unknown
        }
    }

    public enum DetectionType: String, Codable, Sendable {
        case smoke, fire, smokeAndFire, thermalAnomaly
    }

    public enum TemperatureQuality: String, Codable, Sendable {
        case calibrated, uncalibrated, missing

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .missing
        }
    }

    public let version: Int
    public let sourceKey: String
    public let displayNumber: Int
    public let sessionID: String
    public let zoneID: String
    public let zoneName: String
    public let subzoneID: String?
    public let subzoneName: String?
    public let source: Source
    public let detectionType: DetectionType?
    public let capturedAt: Date?
    public let captureTimeText: String?
    public let peakTemperatureC: Double?
    public let temperatureQuality: TemperatureQuality
    public let riskLevel: HotspotCloudRiskLevel

    public init(
        version: Int = 1, sourceKey: String, displayNumber: Int, sessionID: String,
        zoneID: String, zoneName: String, subzoneID: String? = nil, subzoneName: String? = nil,
        source: Source, detectionType: DetectionType? = nil, capturedAt: Date? = nil,
        captureTimeText: String? = nil, peakTemperatureC: Double? = nil,
        temperatureQuality: TemperatureQuality = .missing, riskLevel: HotspotCloudRiskLevel = .unknown
    ) {
        self.version = version
        self.sourceKey = sourceKey
        self.displayNumber = displayNumber
        self.sessionID = sessionID
        self.zoneID = zoneID
        self.zoneName = zoneName
        self.subzoneID = subzoneID
        self.subzoneName = subzoneName
        self.source = source
        self.detectionType = detectionType
        self.capturedAt = capturedAt
        self.captureTimeText = captureTimeText
        self.peakTemperatureC = peakTemperatureC
        self.temperatureQuality = temperatureQuality
        self.riskLevel = riskLevel
    }

    private enum CodingKeys: String, CodingKey {
        case version, sourceKey, displayNumber, sessionID, zoneID, zoneName, subzoneID, subzoneName
        case source, detectionType, capturedAt, captureTimeText, peakTemperatureC, temperatureQuality, riskLevel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sourceKey = try values.decode(String.self, forKey: .sourceKey)
        displayNumber = try values.decode(Int.self, forKey: .displayNumber)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        zoneID = try values.decode(String.self, forKey: .zoneID)
        zoneName = try values.decode(String.self, forKey: .zoneName)
        subzoneID = try values.decodeIfPresent(String.self, forKey: .subzoneID)
        subzoneName = try values.decodeIfPresent(String.self, forKey: .subzoneName)
        source = try values.decodeIfPresent(Source.self, forKey: .source) ?? .unknown
        detectionType = try values.decodeIfPresent(String.self, forKey: .detectionType).flatMap(DetectionType.init(rawValue:))
        capturedAt = try values.decodeIfPresent(Date.self, forKey: .capturedAt)
        captureTimeText = try values.decodeIfPresent(String.self, forKey: .captureTimeText)
        peakTemperatureC = try values.decodeIfPresent(Double.self, forKey: .peakTemperatureC)
        temperatureQuality = try values.decodeIfPresent(TemperatureQuality.self, forKey: .temperatureQuality) ?? .missing
        riskLevel = try values.decodeIfPresent(HotspotCloudRiskLevel.self, forKey: .riskLevel) ?? .unknown
    }
}
