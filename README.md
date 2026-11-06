# Tilik-Cloudkit

Swift package untuk kontrak payload CloudKit aplikasi Operator dan Petugas. Modul Swift bernama `TilikCloudkit`.

Target aplikasi adalah iOS dan iPadOS 17 atau lebih baru. Swift Package Manager memakai deklarasi `.iOS` untuk keduanya.

Di Xcode pilih **File → Add Package Dependencies**, masukkan `https://github.com/BagusKrishna/Tilik-Cloudkit.git`, pilih versi yang tersedia, lalu tambahkan library `Tilik-Cloudkit` ke target. Gunakan `import TilikCloudkit` dalam Swift.

Untuk Swift Package Manager, tambahkan `.package(url: "https://github.com/BagusKrishna/Tilik-Cloudkit.git", from: "0.3.0")` dan `.product(name: "Tilik-Cloudkit", package: "Tilik-Cloudkit")` ke target.

Package menyediakan model workspace, event, anggota, laporan, snapshot dan antrean collaboration; service sinkronisasi, adapter CloudKit, penyimpanan cache lokal, serta adapter notifikasi dan demo. Pastikan perubahan payload tetap dapat dibaca oleh kedua aplikasi dan versi lama.

Adapter CloudKit menerima `CloudKitEvidenceHandling` dari aplikasi untuk membaca dan menyimpan bukti, sehingga package tidak bergantung pada model AI. Pesan notifikasi dapat disesuaikan melalui `alertBody` dan `formatAlertBody` pada `CollaborationSyncService`; default mempertahankan perilaku sebelumnya. UI tetap berada di aplikasi.

Model tugas dari branch `officer-dispatch` belum dipindahkan. Package ini tidak membuat atau menerapkan schema CloudKit; schema tetap dikelola dalam container CloudKit.
