import Cocoa

extension AppDelegate {
    func cariKextTurboBoost() -> String? {
        var kandidat: [String] = []
        if let bawaan = Bundle.main.resourceURL?.appendingPathComponent("DisableTurboBoost.64bits.kext").path {
            kandidat.append(bawaan)
        }
        kandidat.append(contentsOf: [
            "/Applications/Turbo Boost Switcher.app/Contents/Resources/DisableTurboBoost.64bits.kext",
            "/Applications/Turbo Boost Switcher Pro.app/Contents/Resources/DisableTurboBoost.64bits.kext"
        ])
        return kandidat.first { FileManager.default.fileExists(atPath: $0) }
    }

    func cekTurboBoostMati() -> Bool {
        let proses = Process()
        proses.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
        let pipa = Pipe()
        proses.standardOutput = pipa
        try? proses.run()
        proses.waitUntilExit()
        let data = pipa.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains("DisableTurboBoost")
    }

    @objc func pilihModeTurboBoost(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ModeTurboBoost(rawValue: raw) else { return }
        turboDimatiinKarenaTutupLayar = false
        switch mode {
        case .selaluAktif:
            if cacheTurboMati {
                guard setTurboBoostMati(false, tampilinAlert: true) else { return }
            }
            modeTurboBoost = .selaluAktif
        case .matiPasTutupLayar:
            if !FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
                guard pastiinSudoersSiap() else { return }
            }
            modeTurboBoost = .matiPasTutupLayar
            pastiinCegahSleepNyala()
            if cacheTurboMati && !lagiTutupLayar() {
                _ = setTurboBoostMati(false, tampilinAlert: true)
            }
        case .selaluMati:
            if !cacheTurboMati {
                guard setTurboBoostMati(true, tampilinAlert: true) else { return }
            }
            modeTurboBoost = .selaluMati
        }
        aturPantauTutupLayar()
    }

    func setTurboBoostMati(_ matiin: Bool, tampilinAlert: Bool) -> Bool {
        guard let pathKext = cariKextTurboBoost() else {
            if tampilinAlert {
                let alert = NSAlert()
                alert.messageText = "Turbo Boost Switcher Belum Terpasang"
                alert.informativeText = "macOS tidak memiliki perintah bawaan untuk mematikan Turbo Boost. Pasang aplikasi Turbo Boost Switcher di folder Applications agar DontDoze dapat menggunakan kernel extension-nya."
                alert.alertStyle = .informational
                alert.runModal()
            }
            return false
        }

        if matiin {
            if jalaninPerintahSudo("/usr/sbin/chown -R root:wheel '\(pathKext)'", tampilinAlertError: tampilinAlert) &&
               jalaninPerintahSudo("/sbin/kextload '\(pathKext)'", tampilinAlertError: tampilinAlert) {
                cacheTurboMati = true
                return true
            }
        } else {
            if jalaninPerintahSudo("/sbin/kextunload '\(pathKext)'", tampilinAlertError: tampilinAlert) {
                cacheTurboMati = false
                return true
            }
        }
        return false
    }

    func balikinTurboBoostKalauPerlu() {
        #if arch(x86_64)
        if turboDimatiinKarenaTutupLayar {
            turboDimatiinKarenaTutupLayar = false
            if FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self = self else { return }
                    if self.setTurboBoostMati(false, tampilinAlert: false) {
                        self.tulisLogSuspend("TURBO BOOST: Restored on lid open")
                    }
                }
            }
        }
        #endif
    }
}
