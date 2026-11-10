/// Names used by the existing CloudKit collaboration schema.
/// Adding a constant does not create a field in CloudKit; records must be saved
/// in Development and schema changes deployed separately to Production.
public enum TilikCloudKitSchema {
    public enum RecordType {
        public static let workspace = "TilikWorkspace"
        public static let hotspot = "TilikHotspot"
        public static let ping = "TilikPing"
        public static let response = "TilikResponse"
        public static let subzoneRun = "TilikSubzoneRun"
        public static let officerProfile = "TilikOfficerProfile"
        public static let officerIdentity = "TilikOfficerIdentity"
        public static let events = [hotspot, ping, response, subzoneRun]
    }

    /// Workspace: workspaceID, name, ownerAccountID are String; schemaVersion is Int64.
    /// Events: workspaceID is String; payload is JSON encoded as Data (Bytes).
    /// Hotspot images, hazard evidence and the response inspection photo are optional Assets.
    /// Evidence fields are populated by the app-specific evidence handler.
    public enum Field {
        public static let workspaceID = "workspaceID"
        public static let name = "name"
        public static let ownerAccountID = "ownerAccountID"
        public static let schemaVersion = "schemaVersion"
        public static let payload = "payload"
        public static let rgbImage = "rgbImage"
        public static let thermalImage = "thermalImage"
        public static let inspectionPhoto = "inspectionPhoto"
        public static let evidence = "evidence"
        public static let annotatedEvidence = "annotatedEvidence"
        public static let evidenceMetadata = "evidenceMetadata"
        public static let participantID = "participantID"
        public static let email = "email"
    }
}
