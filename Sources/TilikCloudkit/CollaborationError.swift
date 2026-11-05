//
//  CollaborationError.swift
//  Tilik
//
//  Created by Gede Bagus Krishnanditya Merta on 20/10/26.
//

import Foundation

public enum CollaborationError: LocalizedError {
    case accountUnavailable, invalidShare, ownInvitation, alreadyJoined, notOwner
    case invitationRequiresNewerOS, oneTimeLinksUnavailable, invalidWorkspace, targetUnavailable, conflictingEvent, queueFull,
        busy,
        resetIncomplete
    case configurationMissing, workspaceExists, invalidName, pendingChanges, membershipPending, connectionTimedOut

    public var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "iCloud belum tersedia. Masuk ke akun iCloud di Pengaturan, lalu coba lagi."
        case .invalidShare:
            return "Undangan atau akses berbagi tidak valid. Minta undangan baru dari operator."
        case .ownInvitation: return "Operator tidak dapat menerima undangan TPA miliknya sendiri."
        case .alreadyJoined:
            return "Akun ini sudah tergabung sebagai petugas di TPA lain. Undangan belum diterima."
        case .notOwner: return "Aksi ini hanya dapat dilakukan pemilik TPA."
        case .invitationRequiresNewerOS:
            return "Undangan QR sekali pakai memerlukan iOS 18 atau lebih baru."
        case .oneTimeLinksUnavailable:
            return "Build Tilik ini belum memiliki izin iCloud untuk undangan sekali pakai. Periksa entitlement InProcessOneTimeLinks dan provisioning profile."
        case .invalidWorkspace: return "Data TPA tidak sesuai versi yang didukung. Hubungi operator."
        case .targetUnavailable: return "Titik panas sudah tidak tersedia. Respons dihentikan."
        case .conflictingEvent:
            return "ID kiriman sudah digunakan oleh data berbeda. Kiriman perlu diperiksa."
        case .queueFull: return "Antrean kiriman penuh. Periksa kiriman tertunda sebelum menambah data."
        case .busy: return "Pengelolaan TPA sedang berlangsung. Coba lagi setelah selesai."
        case .resetIncomplete:
            return
                "Reset belum selesai; sebagian data mungkin sudah dihapus. Pilih Reset Data TPA lagi untuk melanjutkan."
        case .workspaceExists:
            return "TPA milik Anda sudah tersedia. Muat ulang dan pilih TPA tersebut."
        case .invalidName: return "Isi nama TPA terlebih dahulu."
        case .pendingChanges: return "Masih ada kiriman yang belum tersinkron. Selesaikan kiriman tersebut sebelum menghapus koneksi."
        case .membershipPending:
            return "Undangan diterima, tetapi TPA belum muncul di iCloud. Coba muat ulang koneksi tanpa memindai QR lagi."
        case .connectionTimedOut:
            return "iCloud belum merespons dalam 30 detik. Periksa koneksi internet, lalu coba lagi. Data tersimpan tetap tersedia."
        case .configurationMissing:
            return
                "Sinkronisasi iCloud belum diaktifkan pada build ini. Data antarperangkat belum terhubung. Hubungi pengembang untuk mengaktifkannya."
        }
    }
}
