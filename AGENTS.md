# Petunjuk untuk agent

Package ini mendefinisikan kontrak payload yang dibaca aplikasi Tilik Operator dan Petugas. Modul Swift adalah `TilikCloudkit`; produk Swift Package adalah `Tilik-Cloudkit`.

- Pertahankan nama field JSON, raw value enum, dan kemampuan membaca payload lama kecuali ada rencana migrasi yang disetujui.
- Tambahkan field baru dengan default atau sifat opsional bila memungkinkan. Pertimbangkan aplikasi lama yang masih terpasang.
- Perubahan model tidak otomatis mengubah schema CloudKit di server. Package ini tidak mengelola container atau entitlement.
- Jangan menyimpan identifier akun, kredensial, atau konfigurasi signing developer dalam repository.
- Periksa kedua aplikasi konsumen dan jalankan pengujian kompatibilitas payload saat mengubah kontrak.
