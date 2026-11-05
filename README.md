# Tilik-Cloudkit

Swift package untuk kontrak payload CloudKit aplikasi Operator dan Petugas. Modul Swift bernama `TilikCloudkit`.

Target aplikasi adalah iOS dan iPadOS 17 atau lebih baru. Swift Package Manager memakai deklarasi `.iOS` untuk keduanya.

Di Xcode pilih **File → Add Package Dependencies**, masukkan `https://github.com/BagusKrishna/Tilik-Cloudkit.git`, pilih versi yang tersedia, lalu tambahkan library `Tilik-Cloudkit` ke target. Gunakan `import TilikCloudkit` dalam Swift.

Untuk Swift Package Manager, tambahkan `.package(url: "https://github.com/BagusKrishna/Tilik-Cloudkit.git", from: "0.1.0")` dan `.product(name: "Tilik-Cloudkit", package: "Tilik-Cloudkit")` ke target.

Versi awal menyediakan `CollaborationHotspotDetails` dan `HotspotCloudRiskLevel`. Pastikan perubahan payload tetap dapat dibaca oleh kedua aplikasi dan versi lama.

Model tugas dari branch `officer-dispatch`, model lainnya, dan service CloudKit belum dipindahkan. Package ini tidak membuat atau menerapkan schema CloudKit; schema tetap dikelola dalam container CloudKit.
