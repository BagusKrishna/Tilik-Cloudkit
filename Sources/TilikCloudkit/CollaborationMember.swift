//
//  CollaborationMember.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

/// Session-only identity from CKShare. Never persist names or contacts in the event cache.
public struct CollaborationMember: Identifiable, Equatable {
    public enum Permission: Equatable {
        case readOnly, readWrite, unknown
    }

    public let id: String
    public let name: String?
    public let email: String?
    public let permission: Permission
    public let isOwner: Bool

    public init(
        id: String, name: String? = nil, email: String? = nil,
        permission: Permission = .unknown, isOwner: Bool = false
    ) {
        self.id = id
        self.name = Self.nonempty(name)
        self.email = Self.nonempty(email)
        self.permission = permission
        self.isOwner = isOwner
    }

    public var title: String { name ?? email ?? (isOwner ? "Anda" : "Identitas belum tersedia") }
    /// Email is preferred on the connected accounts screen; CKShare can omit it.
    public var connectedAccountTitle: String { email ?? name ?? "Identitas belum tersedia" }
    public var subtitle: String? { name != nil ? email : nil }
    public var initials: String? {
        if let name {
            return String(name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)).uppercased()
        }
        return email?.first.map { String($0).uppercased() }
    }
    public var accessDescription: String {
        if isOwner { return "Anda · Pemilik" }
        switch permission {
        case .readOnly: return "Hanya dapat melihat data TPA"
        case .readWrite: return "Dapat memperbarui data TPA"
        case .unknown: return "Izin akses belum tersedia"
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
