import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var prosesCaffeinate: Process?
    var lagiTerjaga = false
    var cacheSleepDimatiin = false
    var cacheNilaiDaya: [String: Int] = [:]
    var cacheTurboMati = false

    let keyBahasa = "AppLanguage"
    let keyIkonMenuBar = "MenuBarIcon"
    let keySuspendTutupLayar = "FreezeAppsOnLidClose"
    let keyModeTurboBoost = "TurboBoostMode"
    let keyUdahTanyaSudoers = "HasPromptedSudoersSetup"
    let keyModeLanjutan = "AdvancedMode"
    let keySisaPIDKeSuspend = "LeftoverFrozenPIDs"

    var timerPantauLayar: Timer?
    var statusTerakhirLayarTutup = false
    var daftarPIDKeSuspend: Set<pid_t> = []
    var turboDimatiinKarenaTutupLayar = false

    let labelLaunchAgent = "com.rizki.DontDoze"
    var urlLaunchAgent: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(labelLaunchAgent).plist")
    }

    var suspendPasTutupLayar: Bool {
        get { UserDefaults.standard.bool(forKey: keySuspendTutupLayar) }
        set { UserDefaults.standard.set(newValue, forKey: keySuspendTutupLayar) }
    }

    var modeTurboBoost: ModeTurboBoost {
        get {
            let raw = UserDefaults.standard.string(forKey: keyModeTurboBoost) ?? ModeTurboBoost.selaluAktif.rawValue
            return ModeTurboBoost(rawValue: raw) ?? .selaluAktif
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: keyModeTurboBoost)
        }
    }

    var ikonKepilih: IkonMenuBar {
        get {
            let raw = UserDefaults.standard.string(forKey: keyIkonMenuBar) ?? IkonMenuBar.zzz.rawValue
            return IkonMenuBar(rawValue: raw) ?? .zzz
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: keyIkonMenuBar)
        }
    }

    var modeLanjutan: Bool {
        get { UserDefaults.standard.bool(forKey: keyModeLanjutan) }
        set { UserDefaults.standard.set(newValue, forKey: keyModeLanjutan) }
    }

    var bahasaKepilih: BahasaApp {
        get {
            let raw = UserDefaults.standard.string(forKey: keyBahasa) ?? BahasaApp.system.rawValue
            return BahasaApp(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: keyBahasa)
        }
    }

    var bahasaAktif: BahasaApp {
        switch bahasaKepilih {
        case .system:
            return (Locale.preferredLanguages.first?.hasPrefix("id") == true) ? .id : .en
        case .id, .en:
            return bahasaKepilih
        }
    }

    func teks(_ indo: String, _ inggris: String) -> String {
        bahasaAktif == .id ? indo : inggris
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let tombol = statusItem.button {
            tombol.target = self
            tombol.action = #selector(ikonMenuBarDiklik(_:))
            tombol.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        pulihinSisaAplikasiKeSuspend()
        let outputPmset = bacaOutputPmset()
        cacheSleepDimatiin = cekSleepDisabled(di: outputPmset)
        cacheNilaiDaya = parseNilaiPmset(di: outputPmset)
        if cacheSleepDimatiin {
            nyalainCaffeinate()
            lagiTerjaga = true
        }
        if !modeLanjutan && suspendPasTutupLayar {
            suspendPasTutupLayar = false
        }
        updateIkon()

        DispatchQueue.global(qos: .utility).async {
            let statusTurbo = self.cekTurboBoostMati()
            DispatchQueue.main.async {
                self.cacheTurboMati = statusTurbo
                if UserDefaults.standard.string(forKey: self.keyModeTurboBoost) == nil {
                    self.modeTurboBoost = statusTurbo ? .selaluMati : .selaluAktif
                } else if self.modeTurboBoost == .selaluMati && !statusTurbo && FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
                    DispatchQueue.global(qos: .utility).async {
                        _ = self.setTurboBoostMati(true, tampilinAlert: false)
                    }
                }
            }
        }
        aturPantauTutupLayar()
        DispatchQueue.main.async {
            self.tanyaPasangIzinAwal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        lanjutinAplikasiKeSuspend()
        matiinCaffeinate()
        if cacheSleepDimatiin && FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
            _ = jalaninPmsetAdmin("disablesleep 0")
            cacheSleepDimatiin = false
        }
    }

    @objc func ikonMenuBarDiklik(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            tampilinMenu()
        } else {
            toggleModeSemua()
        }
    }

    var statusTeks: String {
        guard modeLanjutan else {
            return lagiTerjaga
                ? teks("Mac tetap terjaga", "Mac will stay awake")
                : teks("Mac bisa tidur", "Mac can go to sleep")
        }
        switch (lagiTerjaga, cacheSleepDimatiin) {
        case (true, true):
            return teks("Mac tetap terjaga", "Mac will stay awake")
        case (true, false):
            return teks("Mac tetap terjaga (tidur jika layar ditutup)", "Mac will stay awake (sleeps if lid closed)")
        case (false, true):
            return teks("Mac bisa tidur saat idle, tetap menyala saat layar ditutup", "Mac can idle sleep, stays awake on lid close")
        case (false, false):
            return teks("Mac bisa tidur", "Mac can go to sleep")
        }
    }

    var statusTeksAttributed: NSAttributedString {
        NSAttributedString(
            string: statusTeks,
            attributes: [
                .font: NSFont.menuFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    func tampilinMenu() {
        let menu = NSMenu()
        let itemStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        itemStatus.attributedTitle = statusTeksAttributed
        itemStatus.isEnabled = false
        menu.addItem(itemStatus)

        var itemSleepLayar: NSMenuItem?
        if modeLanjutan {
            let itemLayar = NSMenuItem(title: teks("Jaga Layar Tetap Menyala", "Keep Display Awake"), action: #selector(toggleLayarAja), keyEquivalent: "")
            itemLayar.target = self
            itemLayar.state = lagiTerjaga ? .on : .off
            menu.addItem(itemLayar)

            let itemSistem = NSMenuItem(title: teks("Tetap Nyalakan Sistem saat Layar Ditutup", "Keep System Awake on Lid Close"), action: #selector(toggleSleepSistem), keyEquivalent: "")
            itemSistem.target = self
            itemSistem.state = cacheSleepDimatiin ? .on : .off
            menu.addItem(itemSistem)
            itemSleepLayar = itemSistem
        } else {
            let judulToggle = (lagiTerjaga || cacheSleepDimatiin)
                ? teks("Izinkan Perangkat Tidur", "Allow Device Sleep")
                : teks("Jaga Tetap Menyala", "Keep Device Awake")
            let itemToggle = NSMenuItem(title: judulToggle, action: #selector(toggleModeSemua), keyEquivalent: "")
            itemToggle.target = self
            menu.addItem(itemToggle)
        }

        menu.addItem(NSMenuItem.separator())

        #if arch(x86_64)
        let menuTurbo = NSMenu()
        var daftarItemTurbo: [ModeTurboBoost: NSMenuItem] = [:]
        let opsiTurbo: [(String, ModeTurboBoost)] = [
            (teks("Selalu Aktif", "Always Enabled"), .selaluAktif),
            (teks("Matikan saat Layar Ditutup", "Disable When Lid Close"), .matiPasTutupLayar),
            (teks("Selalu Mati", "Always Disabled"), .selaluMati)
        ]
        for (judul, mode) in opsiTurbo {
            let item = NSMenuItem(title: judul, action: #selector(pilihModeTurboBoost(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (modeTurboBoost == mode) ? .on : .off
            menuTurbo.addItem(item)
            daftarItemTurbo[mode] = item
        }

        let parentTurbo = NSMenuItem(title: teks("Status Turbo Boost", "Turbo Boost Status"), action: nil, keyEquivalent: "")
        parentTurbo.submenu = menuTurbo
        menu.addItem(parentTurbo)
        #else
        let daftarItemTurbo: [ModeTurboBoost: NSMenuItem] = [:]
        #endif

        var itemSuspend: NSMenuItem?
        var itemJanganSuspend: NSMenuItem?
        var daftarItemDaya: [String: NSMenuItem] = [:]
        if modeLanjutan {
            let menuSuspend = NSMenu()
            let itemS = NSMenuItem(title: teks("Suspend saat Layar Ditutup", "Suspend When Lid Close"), action: #selector(pilihModeSuspendAplikasi(_:)), keyEquivalent: "")
            itemS.target = self
            itemS.representedObject = true
            itemS.state = suspendPasTutupLayar ? .on : .off
            menuSuspend.addItem(itemS)
            itemSuspend = itemS

            let itemNS = NSMenuItem(title: teks("Jangan Suspend Aplikasi", "Don't Suspend Apps"), action: #selector(pilihModeSuspendAplikasi(_:)), keyEquivalent: "")
            itemNS.target = self
            itemNS.representedObject = false
            itemNS.state = !suspendPasTutupLayar ? .on : .off
            menuSuspend.addItem(itemNS)
            itemJanganSuspend = itemNS

            menuSuspend.addItem(NSMenuItem.separator())

            let itemLog = NSMenuItem(title: teks("Lihat Log...", "View Log..."), action: #selector(bukaLogSuspend), keyEquivalent: "")
            itemLog.target = self
            menuSuspend.addItem(itemLog)

            let parentSuspend = NSMenuItem(title: teks("Suspend Aplikasi Berjalan", "Suspend Running Apps"), action: nil, keyEquivalent: "")
            parentSuspend.submenu = menuSuspend
            menu.addItem(parentSuspend)

            let menuDaya = NSMenu()
            for opsi in daftarOpsiDaya where cacheNilaiDaya[opsi.key] != nil {
                let item = NSMenuItem(title: teks(opsi.judulID, opsi.judulEN), action: #selector(toggleOpsiDaya(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = opsi.key
                item.state = ((cacheNilaiDaya[opsi.key] ?? 0) != opsi.nilaiMati) ? .on : .off
                menuDaya.addItem(item)
                daftarItemDaya[opsi.key] = item
            }
            menuDaya.addItem(NSMenuItem.separator())
            let itemReset = NSMenuItem(title: teks("Reset ke Default...", "Reset to Defaults..."), action: #selector(resetOpsiDaya), keyEquivalent: "")
            itemReset.target = self
            menuDaya.addItem(itemReset)

            let parentDaya = NSMenuItem(title: teks("Manajemen Daya", "Power Management"), action: nil, keyEquivalent: "")
            parentDaya.submenu = menuDaya
            menu.addItem(parentDaya)
        }

        menu.addItem(NSMenuItem.separator())

        let menuPengaturan = NSMenu()
        let itemLogin = NSMenuItem(title: teks("Buka Otomatis saat Login", "Launch at Login"), action: #selector(toggleLaunchPasLogin), keyEquivalent: "")
        itemLogin.target = self
        itemLogin.state = cekLaunchPasLogin() ? .on : .off
        menuPengaturan.addItem(itemLogin)

        let itemLanjutan = NSMenuItem(title: teks("Mode Lanjutan", "Advanced Mode"), action: #selector(toggleModeLanjutan), keyEquivalent: "")
        itemLanjutan.target = self
        itemLanjutan.state = modeLanjutan ? .on : .off
        menuPengaturan.addItem(itemLanjutan)

        menuPengaturan.addItem(NSMenuItem.separator())

        let udahAdaSudoers = FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze")
        let judulIzin = udahAdaSudoers
            ? teks("Hapus Helper...", "Remove Helper...")
            : teks("Pasang Helper...", "Install Helper...")
        let aksiIzin = udahAdaSudoers ? #selector(hapusIzin) : #selector(pasangIzin)
        let itemIzin = NSMenuItem(title: judulIzin, action: aksiIzin, keyEquivalent: "")
        itemIzin.target = self
        menuPengaturan.addItem(itemIzin)

        menuPengaturan.addItem(NSMenuItem.separator())

        let menuIkon = NSMenu()
        let pilihanIkon: [(String, IkonMenuBar)] = [
            ("Default", .zzz),
            ("MacBook", .laptopcomputer),
            (teks("Cangkir Kopi", "Coffee Cup"), .coffee)
        ]
        for (judul, ikon) in pilihanIkon {
            let item = NSMenuItem(title: judul, action: #selector(pilihIkonMenuBar(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ikon.rawValue
            item.state = (ikonKepilih == ikon) ? .on : .off
            item.image = ambilIkonStatusBar(buat: ikon)
            menuIkon.addItem(item)
        }
        let parentIkon = NSMenuItem(title: teks("Ikon Menu Bar", "Menu Bar Icon"), action: nil, keyEquivalent: "")
        parentIkon.submenu = menuIkon
        menuPengaturan.addItem(parentIkon)

        let menuBahasa = NSMenu()
        let opsiBahasa: [(String, BahasaApp)] = [
            (teks("Ikuti Sistem", "Follow System"), .system),
            ("Indonesia", .id),
            ("English", .en)
        ]
        for (judul, bhs) in opsiBahasa {
            let item = NSMenuItem(title: judul, action: #selector(pilihBahasa(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bhs.rawValue
            item.state = (bahasaKepilih == bhs) ? .on : .off
            menuBahasa.addItem(item)
        }
        let parentBahasa = NSMenuItem(title: teks("Bahasa", "Language"), action: nil, keyEquivalent: "")
        parentBahasa.submenu = menuBahasa
        menuPengaturan.addItem(parentBahasa)

        let parentPengaturan = NSMenuItem(title: teks("Pengaturan", "Preferences"), action: nil, keyEquivalent: "")
        parentPengaturan.submenu = menuPengaturan
        menu.addItem(parentPengaturan)

        let itemKeluar = NSMenuItem(title: teks("Keluar", "Quit"), action: #selector(keluarApp), keyEquivalent: "q")
        itemKeluar.target = self
        menu.addItem(itemKeluar)

        refreshStatusSistem(itemStatus: itemStatus, itemSleep: itemSleepLayar, itemSuspend: itemSuspend, itemJanganSuspend: itemJanganSuspend, daftarItemDaya: daftarItemDaya, daftarItemTurbo: daftarItemTurbo)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func refreshStatusSistem(itemStatus: NSMenuItem? = nil, itemSleep: NSMenuItem? = nil, itemSuspend: NSMenuItem? = nil, itemJanganSuspend: NSMenuItem? = nil, daftarItemDaya: [String: NSMenuItem] = [:], daftarItemTurbo: [ModeTurboBoost: NSMenuItem] = [:]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak itemStatus, weak itemSleep, weak itemSuspend, weak itemJanganSuspend] in
            guard let self = self else { return }
            let outputPmset = self.bacaOutputPmset()
            let sleepDimatiin = self.cekSleepDisabled(di: outputPmset)
            let nilaiDaya = self.parseNilaiPmset(di: outputPmset)
            #if arch(x86_64)
            let turboMati = self.cekTurboBoostMati()
            #endif
            RunLoop.main.perform(inModes: [.common]) {
                self.cacheSleepDimatiin = sleepDimatiin
                self.cacheNilaiDaya = nilaiDaya
                if !sleepDimatiin {
                    self.lanjutinAplikasiKeSuspend()
                }
                itemSleep?.state = sleepDimatiin ? .on : .off
                itemSuspend?.state = self.suspendPasTutupLayar ? .on : .off
                itemJanganSuspend?.state = !self.suspendPasTutupLayar ? .on : .off
                if let sm = itemStatus {
                    sm.attributedTitle = self.statusTeksAttributed
                    sm.menu?.itemChanged(sm)
                }
                self.updateIkon()
                for opsi in daftarOpsiDaya {
                    if let item = daftarItemDaya[opsi.key], let nilai = nilaiDaya[opsi.key] {
                        item.state = (nilai != opsi.nilaiMati) ? .on : .off
                    }
                }
                #if arch(x86_64)
                self.cacheTurboMati = turboMati
                if self.modeTurboBoost != .matiPasTutupLayar {
                    self.modeTurboBoost = turboMati ? .selaluMati : .selaluAktif
                    for (mode, item) in daftarItemTurbo {
                        item.state = (mode == self.modeTurboBoost) ? .on : .off
                    }
                }
                #endif
            }
        }
    }

    @objc func pilihBahasa(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let bhs = BahasaApp(rawValue: raw) else { return }
        bahasaKepilih = bhs
        updateIkon()
    }

    @objc func toggleModeLanjutan() {
        modeLanjutan.toggle()
        if !modeLanjutan {
            if suspendPasTutupLayar {
                suspendPasTutupLayar = false
                lanjutinAplikasiKeSuspend()
            }
            if lagiTerjaga && !cacheSleepDimatiin && FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
                pastiinCegahSleepNyala()
            }
        }
        aturPantauTutupLayar()
        updateIkon()
    }

    @objc func keluarApp() {
        lanjutinAplikasiKeSuspend()
        matiinCaffeinate()
        NSApp.terminate(nil)
    }
}
