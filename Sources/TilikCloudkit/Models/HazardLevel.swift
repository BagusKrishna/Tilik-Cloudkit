import Foundation

public enum HazardLevel: String, Codable, Sendable, CaseIterable {
    case smoke, fire, smokeAndFire

    public var rank: Int {
        switch self {
        case .smoke: return 1
        case .fire: return 2
        case .smokeAndFire: return 3
        }
    }

    public var alertTitle: String {
        switch self {
        case .smoke: return "Asap Terdeteksi"
        case .fire: return "Api Terdeteksi"
        case .smokeAndFire: return "Asap dan Api Terdeteksi"
        }
    }

    /// "Asap", "Api" or "Asap dan Api", for sentences such as "Drone mendeteksi Api pada sub zona A2".
    public var phrase: String {
        switch self {
        case .smoke: return "Asap"
        case .fire: return "Api"
        case .smokeAndFire: return "Asap dan Api"
        }
    }

    public func alertMessage(subzoneLabel: String?, zoneName: String) -> String {
        if let subzoneLabel, !subzoneLabel.isEmpty {
            return "Drone mendeteksi \(phrase) pada sub zona \(subzoneLabel)"
        }
        return zoneName.isEmpty ? "Drone mendeteksi \(phrase)" : "Drone mendeteksi \(phrase) di \(zoneName)"
    }
}
