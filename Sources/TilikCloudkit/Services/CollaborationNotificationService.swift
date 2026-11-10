#if os(iOS)
//
//  CollaborationNotificationService.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation
import UserNotifications
import CryptoKit

@MainActor
public final class CollaborationNotificationService: CollaborationAlertServing {
    private let title: String

    public init(title: String = "Tilik") { self.title = title }
    public func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func schedule(id: String, body: String) async throws -> Bool {
        try await schedule(id: id, body: body, route: [:])
    }

    public func schedule(id: String, body: String, route: [String: String]) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return false }
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = route
        content.sound = .default
        let request = UNNotificationRequest(identifier: "tilik-collab-" + digest, content: content, trigger: nil)
        try await center.add(request)
        return true
    }

    public func cancelPending() {
        Task {
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(
                withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("tilik-collab-") })
        }
    }
}

#endif
