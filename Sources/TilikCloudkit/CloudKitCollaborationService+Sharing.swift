#if os(iOS)
import CloudKit

/// Native sharing presentation consumes this bridge; the main ViewModel stays CloudKit-free.
public struct CollaborationNativeShare {
    public let share: CKShare
    public let container: CKContainer
}

@MainActor
public protocol CollaborationNativeSharingProviding {
    func nativeShare(for workspace: TPAWorkspace) async throws -> CollaborationNativeShare?
}

extension CloudKitCollaborationService: CollaborationNativeSharingProviding {
    public func nativeShare(for workspace: TPAWorkspace) async throws -> CollaborationNativeShare? {
        try await verifyOwner(workspace)
        guard let share = try await fetchShare(workspace) else { return nil }
        return CollaborationNativeShare(share: share, container: container)
    }
}

#endif
