import Cocoa

extension AppDelegate {
    @objc func toggleModeSemua() {
        if lagiTerjaga || cacheSleepDimatiin {
            matiinCaffeinate()
            lagiTerjaga = false
            if cacheSleepDimatiin && jalaninPmsetAdmin("disablesleep 0") {
                cacheSleepDimatiin = false
                lanjutinAplikasiKeSuspend()
                aturPantauTutupLayar()
            }
        } else {
            nyalainCaffeinate()
            lagiTerjaga = true
            if !cacheSleepDimatiin && FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
                if jalaninPmsetAdmin("disablesleep 1") {
                    cacheSleepDimatiin = true
                    aturPantauTutupLayar()
                }
            }
        }
        updateIkon()
    }

    @objc func toggleLayarAja() {
        if lagiTerjaga {
            matiinCaffeinate()
            lagiTerjaga = false
        } else {
            nyalainCaffeinate()
            lagiTerjaga = true
        }
        updateIkon()
    }

    @objc func toggleSleepSistem() {
        let target = cacheSleepDimatiin ? "disablesleep 0" : "disablesleep 1"
        if jalaninPmsetAdmin(target) {
            cacheSleepDimatiin.toggle()
            if !cacheSleepDimatiin {
                lanjutinAplikasiKeSuspend()
            }
            aturPantauTutupLayar()
            updateIkon()
        }
    }

    func pastiinCegahSleepNyala() {
        let statusSekarang = cekSleepDisabled(di: bacaOutputPmset())
        cacheSleepDimatiin = statusSekarang
        guard !statusSekarang else { return }
        if FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") || pastiinSudoersSiap() {
            if jalaninPmsetAdmin("disablesleep 1") {
                cacheSleepDimatiin = true
                updateIkon()
            }
        }
    }

    func nyalainCaffeinate() {
        guard prosesCaffeinate == nil else { return }
        let proses = Process()
        proses.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proses.arguments = ["-d", "-i", "-m", "-s"]
        try? proses.run()
        prosesCaffeinate = proses
    }

    func matiinCaffeinate() {
        prosesCaffeinate?.terminate()
        prosesCaffeinate = nil
    }

    @objc func toggleOpsiDaya(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let opsi = daftarOpsiDaya.first(where: { $0.key == key }) else { return }
        let lagiNyala = (cacheNilaiDaya[opsi.key] ?? 0) != opsi.nilaiMati
        let nilaiBaru = lagiNyala ? opsi.nilaiMati : opsi.nilaiAktif
        let target = "\(opsi.key) \(nilaiBaru)"
        if jalaninPmsetAdmin(target) {
            cacheNilaiDaya[opsi.key] = nilaiBaru
        } else if FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
            let alert = NSAlert()
            alert.messageText = teks("Perbarui Izin Sistem?", "Update System Permissions?")
            alert.informativeText = teks(
                "Aturan izin lama belum mencakup semua pengaturan pmset. Perbarui file izin sekarang?",
                "Your existing permission file doesn't cover all pmset options yet. Update it now?"
            )
            alert.addButton(withTitle: teks("Perbarui", "Update"))
            alert.addButton(withTitle: teks("Batal", "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn, pasangFileSudoers(), jalaninPmsetAdmin(target) {
                cacheNilaiDaya[opsi.key] = nilaiBaru
            }
        }
    }

    @objc func resetOpsiDaya() {
        let konfirmasi = NSAlert()
        konfirmasi.alertStyle = .informational
        konfirmasi.messageText = teks("Reset Manajemen Daya ke Default?", "Reset Power Management to Defaults?")
        konfirmasi.informativeText = teks(
            "Ini akan mengembalikan pengaturan standby, autopoweroff, hibernatemode, disksleep, powernap, womp, proximitywake, tcpkeepalive, dan ttyskeepawake ke bawaan macOS.",
            "This will restore standby, autopoweroff, hibernatemode, disksleep, powernap, womp, proximitywake, tcpkeepalive, and ttyskeepawake to macOS defaults."
        )
        konfirmasi.addButton(withTitle: teks("Reset", "Reset"))
        konfirmasi.addButton(withTitle: teks("Batal", "Cancel"))
        guard konfirmasi.runModal() == .alertFirstButtonReturn else { return }

        let defaultArgs = daftarOpsiDaya
            .filter { cacheNilaiDaya[$0.key] != nil }
            .map { "\($0.key) \($0.nilaiAktif)" }
            .joined(separator: " ")
        guard !defaultArgs.isEmpty else { return }
        if jalaninPmsetAdmin(defaultArgs) {
            cacheNilaiDaya = parseNilaiPmset(di: bacaOutputPmset())
        }
    }

    func bacaOutputPmset() -> String {
        let proses = Process()
        proses.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proses.arguments = ["-g"]
        let pipa = Pipe()
        proses.standardOutput = pipa
        try? proses.run()
        proses.waitUntilExit()
        let data = pipa.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func cekSleepDisabled(di output: String) -> Bool {
        output.contains("SleepDisabled\t\t1") || output.contains("SleepDisabled 1")
    }

    func parseNilaiPmset(di output: String) -> [String: Int] {
        var hasil: [String: Int] = [:]
        for baris in output.split(separator: "\n") {
            let bagian = baris.split(whereSeparator: { $0.isWhitespace })
            if bagian.count >= 2, let angka = Int(bagian[1]) {
                hasil[String(bagian[0])] = angka
            }
        }
        return hasil
    }
}
