# Perbaikan chat melalui relay beda grup — 10 November 2026

Status: **perubahan kode dan pengujian otomatis selesai; validasi radio tiga iPhone setelah perbaikan belum dilakukan**.

## 1. Gejala dan batas kesimpulan

Hasil uji lapangan yang dilaporkan pengguna:

| Topologi | Hasil yang dilaporkan |
| --- | --- |
| A dan C satu grup, koneksi langsung | Lokasi, chat, SOS bekerja sampai sekitar 28,8 m. |
| A–B–C satu grup, B di tengah | Jarak A–C mencapai sekitar 58 m. |
| A/C satu grup, B sendiri dalam grup lain | Lokasi dan SOS lewat; chat tidak andal dan jarak efektif lebih pendek. |

Angka jarak tersebut merupakan pengukuran pengguna, bukan hasil pengukuran dari pengujian otomatis ini. Kode tidak menetapkan 28,8 m atau 58 m sebagai batas pengiriman. Tidak ada perubahan daya pancar atau jaminan jangkauan 58 m dalam perbaikan ini.

Lokasi, chat, dan SOS sama-sama memakai frame aplikasi 56 byte. Perbedaan pentingnya ada di penanganan paket: lokasi diperbarui secara berkala, SOS memiliki budget forwarding sendiri, sedangkan chat membutuhkan pesan **dan ACK autentik dari penerima**. Keberhasilan lokasi/SOS saja belum membuktikan jalur chat beserta ACK-nya andal.

## 2. Penyebab yang ditemukan di kode

### A. Pengaturan rate tidak terhubung ke limiter yang berjalan `[VERIFIED]`

`TeeKumConfiguration.Timing.ordinaryRelayRateLimit` tersedia, tetapi initializer `ForwardingRateLimiter` sebelumnya menetapkan refill `2.0` dan kapasitas `4.0` secara langsung. Transport membuat limiter tanpa meneruskan pengaturan tersebut.

Akibatnya, mengubah konstanta pusat tidak mengubah budget relay yang dipakai transport.

Catatan nilai: laporan pengguna menyebut `0.2 → 0.8`. Saat pemeriksaan ini, Git HEAD berisi `2.0` dan workspace sudah diubah menjadi **`8.0`**. Nilai `8.0` tersebut dipertahankan. Angka 0,8, 2, dan 8 diuji secara terpisah; tidak diasumsikan sebagai angka yang sama.

### B. Retry relay lebih lambat daripada timeout chat `[VERIFIED]`

Sebelumnya, `CarryMessageStore` baru mencoba kembali pasangan paket/koneksi setelah **30 detik**, sedangkan `ChatMessageEngine` menunggu ACK selama **15 detik**. Jika pengiriman pertama gagal secara diam-diam atau tertahan budget, kesempatan pemulihan relay bisa datang setelah UI sudah menyatakan timeout.

Retry dari pengirim juga tidak selalu membantu: B memiliki deduplikasi selama beberapa menit, sehingga menerima ulang frame yang sama tidak otomatis membuat B meneruskan frame itu lagi. Pemulihan harus dijalankan oleh penyimpanan ciphertext B sendiri, dengan budget dan batas retry yang terkontrol.

### C. ACK yang hilang tidak dipulihkan oleh penerimaan duplikat `[VERIFIED]`

C sudah menampilkan chat lalu mengirim ACK. Jika ACK itu hilang, A mengirim ulang pesan. Sebelumnya C menolak duplikat tanpa mengirim ACK baru. Hasilnya bisa berupa chat sudah muncul di C, tetapi A tetap melihat pengiriman gagal.

### D. Prioritas paket turun ketika melewati grup lain `[VERIFIED]`

`PriorityOutboxQueue.enqueue(isRelay: true)` sebelumnya memasukkan semua paket asing ke satu antrean relay, termasuk chat, ACK, dan SOS. Artinya jenis paket yang penting kehilangan prioritasnya hanya karena B bukan anggota grup A/C.

Selain itu, lokasi dan chat/ACK memakai token ordinary yang sama tanpa cadangan untuk trafik andal. Replay carry belum mengecualikan koneksi asal, sehingga bisa menghabiskan budget untuk mengirim ciphertext kembali ke koneksi yang baru mengirimkannya.

Temuan-temuan ini menjelaskan mekanisme kegagalan yang dapat direproduksi di perangkat lunak. Tanpa log radio dari percobaan lapangan, kontribusi masing-masing penyebab terhadap jarak yang dilaporkan tetap **belum diketahui**.

## 3. Perubahan yang dilakukan

| File | Perbaikan |
| --- | --- |
| `Core/Mesh/ForwardingRateLimiter.swift` | Default refill ordinary, burst ordinary, dan refill SOS dibaca dari konfigurasi pusat. Telemetri menyisakan satu token burst ordinary untuk chat/ACK; total budget tidak ditambah. |
| `Core/Mesh/MeshProtocols.swift` | Tambahkan operasi konsumsi telemetri dalam budget ordinary yang sama. Implementasi mock tetap kompatibel melalui default protocol extension. |
| `Core/Transport/CarryMessageStore.swift` | Retry cepat per pasangan paket/koneksi: interval 2 detik, sampai 3 percobaan total. Sesudah itu kembali ke interval 30 detik. ACK didahulukan dari chat, koneksi asal dikecualikan, TTL asli dan hop ciphertext tetap dipertahankan. |
| `Core/Transport/PeerTransportService.swift` | Pakai cadangan budget untuk chat/ACK, teruskan identitas koneksi asal ke carry store, hitung attempt sekali saat benar-benar diserahkan ke link, dan periksa ulang generasi sesi/daya/policy setelah menunggu actor lain. Retry asing tidak boleh hidup kembali setelah relay dimatikan. |
| `Core/Transport/PeerTransport.swift` | Kontrak custody menerima koneksi asal yang perlu dikecualikan. |
| `Core/Messaging/PriorityOutboxQueue.swift` | SOS/ACK asing masuk urgent lane; chat asing masuk chat lane. Flag `isRelay` tetap ada agar semua lane asing bisa dibersihkan saat opt-out. |
| `Core/Messaging/PacketRouter.swift` | Teruskan koneksi asal saat mengambil custody. Abaikan pantulan chat/ACK milik sendiri agar pantulan tidak mengubah sasaran retry paket lokal. |
| `Features/Chat/Services/ChatMessageEngine.swift` | Duplikat chat yang sudah lolos autentikasi tetap memperoleh ACK baru, tanpa menampilkan chat kedua atau meneruskan chat tersebut lagi. |
| `Core/Transport/SimulatedMeshTransport.swift` | Samakan pemilihan budget ordinary/telemetri dengan transport produksi. |

B tetap meneruskan ciphertext tanpa kunci grup A/C. Ukuran frame, algoritma enkripsi, batas hop, batas baterai, dan aturan persetujuan relay tetap berlaku. B tidak menampilkan chat atau membunyikan SOS grup lain.

## 4. Konfigurasi yang efektif setelah perbaikan

| Pengaturan | Nilai workspace saat perbaikan | Arti |
| --- | --- | --- |
| `Timing.ordinaryRelayRateLimit` | `8.0` | Token ordinary yang diisi per detik; mencakup forwarding chat, ACK, dan trafik biasa. |
| `Timing.ordinaryRelayBurstCapacity` | `4.0` | Maksimum token ordinary yang bisa terkumpul. Refill 8/detik tidak berarti ada 8 token burst. |
| `Timing.urgentSOSRateLimit` | `4.0` | Refill budget SOS yang terpisah. |
| `Chat.carryFastRetryInterval` | `2.0` detik | Jeda retry cepat per paket/koneksi. |
| `Chat.carryFastAttemptLimit` | `3` | Jumlah penyerahan paket per koneksi pada fase cepat, termasuk percobaan pertama yang tercatat. |
| `Chat.carrySlowRetryInterval` | `30.0` detik | Jeda percobaan berikutnya setelah fase cepat. |
| Timeout ACK chat | `15.0` detik | Batas UI menunggu konfirmasi pengiriman awal. |
| Retensi carry | `600` detik | Custody ciphertext dalam memori; duplikat tidak memperpanjang TTL. |

Rate `0.8` berarti kira-kira satu token setiap 1,25 detik. Sebagian token tetap diperlukan untuk setiap koneksi tujuan; koneksi Wi-Fi/Bluetooth tambahan juga bisa menggunakan budget. Menaikkan rate bukan cara menaikkan daya pancar radio.

Nilai default limiter dibaca saat objek dibuat. Untuk perubahan konstanta source, build dan jalankan ulang aplikasi pada seluruh perangkat. Jangan menggunakan build berbeda untuk A, B, dan C saat membandingkan hasil.

Dengan kapasitas default 4, telemetri dapat memakai 3 token burst terakhir yang tersedia di awal, menyisakan 1 token bagi chat/ACK. Cadangan tersebut tetap berada dalam total budget ordinary. Jika tidak ada token, ciphertext chat/ACK yang sudah ditahan menunggu kesempatan carry berikutnya; bukan diberi budget tanpa batas.

## 5. Bukti pengujian otomatis

| Pengujian | Hasil |
| --- | --- |
| Regresi retry sebelum perbaikan | Gagal pada assertion bahwa retry harus tersedia dalam 2 detik; implementasi lama menunggu 30 detik. |
| Regresi ACK hilang tanpa perbaikan ACK | Gagal karena duplikat chat tidak menghasilkan ACK baru. |
| Kehilangan data dan ACK pada 0,8 / 2 / 8 paket/detik | Lulus: model jalur produksi memakai carry store, limiter, outbox, dan chat engine; pengiriman data B→C pertama serta ACK B→A pertama sengaja dibuang. A memperoleh konfirmasi pada detik ke-8, C menampilkan tepat satu pesan. |
| Privasi dan hop | Ciphertext/tag tetap identik, hop tidak bertambah pada retry; tes router produksi tetap memverifikasi B dengan kunci grup berbeda. |
| Prioritas/policy | ACK asing mendahului chat/lokasi, flag relay bertahan saat retry, opt-out menghapus semua lane asing dan mempertahankan trafik lokal. |
| Carry | Retry cepat dibatasi, fallback 30 detik, koneksi baru, sumber, TTL, kapasitas, dan malformed frame lulus. |
| Build aplikasi dan widget | Build simulator berhasil. |
| Seluruh aplikasi | 17 suite aplikasi selesai; seluruh ringkasan PASS, tanpa penanda kegagalan. |
| CLI | `bash scripts/test-chat.sh` dan `bash scripts/test-carry.sh` lulus. |

Runner aplikasi lama mengabaikan return value suite. Karena itu verifikasi juga memeriksa isi log untuk `FAIL`, assertion, dan ringkasan suite, bukan hanya exit code.

Tes kehilangan paket memakai koneksi yang dimodelkan secara deterministik. Angka pemulihan 8 detik adalah hasil skenario tes tersebut, **bukan janji waktu pengiriman di lapangan**. Pengujian ini tidak mengukur propagasi RF, daya pancar, atau keberhasilan saat iOS menangguhkan aplikasi.

## 6. Langkah pengujian ulang di lapangan

1. Pasang build terbaru yang sama pada A, B, C. Gunakan inisial berbeda. Aktifkan Wi-Fi, Bluetooth, Local Network permission, dan communal relay; baterai minimal 20%, Low Power Mode mati. Awali dengan layar aktif.
2. Buat grup G1 pada A dan gabungkan C memakai invite A. Buat grup G2 tersendiri pada B; B tidak menggunakan invite G1.
3. Uji A–B dan B–C secara langsung pada jarak yang akan digunakan. Kedua segmen harus memiliki koneksi yang masih berfungsi. Uji total 40 m, 50 m, lalu mendekati 58 m secara bertahap dengan B di tengah.
4. Pastikan A–C tidak terhubung langsung melalui Wi-Fi maupun Bluetooth. Matikan B sebagai kontrol: komunikasi A–C harus terputus pada posisi pengujian relay.
5. Dengan B aktif kembali, kirim chat bernomor, misalnya `A01` hingga `A10`, beri jeda minimal 3 detik. Catat terpisah: chat muncul di C, waktu ACK/status delivered di A, dan jumlah pesan duplikat yang terlihat. Ulangi C→A.
6. Ulangi sambil Live Sharing tetap aktif agar lokasi bersaing untuk airtime. Catat jumlah kegagalan dan waktu ACK; jangan menilai hanya dari status ikon koneksi.
7. Picu satu SOS dan periksa C menerima alert, B tetap diam, serta ACK kembali ke A. Jangan memakai keberhasilan SOS sebagai pengganti hasil tes chat.
8. Nonaktifkan lalu aktifkan relay B, kemudian ulangi. Uji juga B keluar jangkauan sesaat lalu kembali. Saat relay B dimatikan, forwarding asing harus berhenti.
9. Bandingkan dengan kontrol semua perangkat satu grup pada posisi fisik yang sama. Setelah baseline foreground selesai, uji layar terkunci sebagai pengujian terpisah dan catat model iPhone, versi iOS, serta kondisi izin.

Format pencatatan yang disarankan:

| Build | Model/iOS A/B/C | Grup B | A–B / B–C | Status layar | Live Sharing | Chat diterima / dikirim | ACK terkonfirmasi / dikirim | Latensi ACK | Duplikat terlihat |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| … | … | sama / beda | … / … m | aktif / terkunci | ON / OFF | … / 10 | … / 10 | … detik | … |

Gunakan nomor uji sintetis dan statistik; jangan menyertakan kunci grup atau koordinat pribadi dalam log yang dibagikan.
