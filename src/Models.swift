import Cocoa

enum BahasaApp: String {
    case system
    case id
    case en
}

enum IkonMenuBar: String {
    case zzz
    case laptopcomputer
    case coffee
}

enum ModeTurboBoost: String {
    case selaluAktif = "alwaysEnabled"
    case matiPasTutupLayar = "disableWhenLidClose"
    case selaluMati = "alwaysDisabled"
}

struct OpsiDaya {
    let key: String
    let judulID: String
    let judulEN: String
    let nilaiAktif: Int
    let nilaiMati: Int
}

let daftarOpsiDaya: [OpsiDaya] = [
    OpsiDaya(key: "standby", judulID: "Deep Sleep Otomatis (Standby)", judulEN: "Auto Deep Sleep (Standby)", nilaiAktif: 1, nilaiMati: 0),
    OpsiDaya(key: "autopoweroff", judulID: "Mati Otomatis saat Sleep Lama", judulEN: "Auto Power Off After Long Sleep", nilaiAktif: 1, nilaiMati: 0),
    OpsiDaya(key: "hibernatemode", judulID: "Simpan Sesi ke SSD saat Sleep (Safe Sleep)", judulEN: "Save Session to SSD on Sleep (Safe Sleep)", nilaiAktif: 3, nilaiMati: 0),
    OpsiDaya(key: "disksleep", judulID: "Izinkan SSD/Disk Tidur saat Idle", judulEN: "Allow SSD/Disk Sleep When Idle", nilaiAktif: 10, nilaiMati: 0),
    OpsiDaya(key: "powernap", judulID: "Aktivitas Latar Belakang saat Sleep (Power Nap)", judulEN: "Background Activity During Sleep (Power Nap)", nilaiAktif: 1, nilaiMati: 0),
    OpsiDaya(key: "womp", judulID: "Bangunkan Mac lewat Jaringan / Wi-Fi", judulEN: "Wake Mac Over Network / Wi-Fi", nilaiAktif: 1, nilaiMati: 0),
    OpsiDaya(key: "proximitywake", judulID: "Bangunkan saat iPhone / Watch di Dekat", judulEN: "Wake When Nearby iPhone / Watch Active", nilaiAktif: 1, nilaiMati: 0),
    OpsiDaya(key: "tcpkeepalive", judulID: "Jaga Koneksi Notifikasi saat Sleep", judulEN: "Keep Notification Connection During Sleep", nilaiAktif: 1, nilaiMati: 0),
    OpsiDaya(key: "ttyskeepawake", judulID: "Tahan Sleep saat Sesi Terminal / SSH Aktif", judulEN: "Stay Awake During Active SSH / Terminal", nilaiAktif: 1, nilaiMati: 0)
]
