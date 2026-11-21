import Cocoa

extension AppDelegate {
    @objc func pasangIzin() {
        if pastiinSudoersSiap() && !modeLanjutan && lagiTerjaga && !cacheSleepDimatiin {
            if jalaninPmsetAdmin("disablesleep 1") {
                cacheSleepDimatiin = true
                updateIkon()
            }
        }
    }

    func tanyaPasangIzinAwal() {
        let pathSudoers = "/etc/sudoers.d/dontdoze"
        guard !FileManager.default.fileExists(atPath: pathSudoers),
              !UserDefaults.standard.bool(forKey: keyUdahTanyaSudoers) else {
            return
        }
        UserDefaults.standard.set(true, forKey: keyUdahTanyaSudoers)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = teks("Pasang Helper Sekali di Awal?", "Install Helper Once?")
        alert.informativeText = teks(
            """
            Agar fitur cegah tidur saat layar ditutup (pmset) dan kontrol Turbo Boost (kextload/kextunload) bisa berjalan otomatis tanpa meminta password berulang kali—termasuk saat layar ditutup—DontDoze perlu membuat aturan terbatas di /etc/sudoers.d/dontdoze.

            Kenapa aman?
            • Hanya mengizinkan perintah spesifik: pmset (pengaturan daya), kextload, kextunload, dan chown kext.
            • Bukan akses admin penuh dan tidak mengubah file sistem lain.
            • Opsional: Anda bisa klik "Nanti Saja" jika hanya memakai mode jaga tetap menyala biasa, atau menghapus izin kapan saja lewat menu "Hapus Helper...".
            """,
            """
            To let Lid-Close Sleep Prevention (pmset) and automatic Turbo Boost control (kextload/kextunload) run silently without repeated password prompts—including when the lid is closed—DontDoze needs to create a restricted rule at /etc/sudoers.d/dontdoze.

            Why is this safe?
            • It only allows specific commands: pmset (power settings), kextload, kextunload, and kext chown.
            • It does not grant full admin access or modify other system files.
            • Optional: click "Later" if you only need basic Keep Awake mode, and you can remove this anytime via "Remove Helper...".
            """
        )
        alert.addButton(withTitle: teks("Pasang Helper", "Install Helper"))
        alert.addButton(withTitle: teks("Nanti Saja", "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            _ = pasangFileSudoers()
        }
    }

    @objc func hapusIzin() {
        let konfirmasi = NSAlert()
        konfirmasi.messageText = teks("Hapus Izin & Bersihkan?", "Remove Permissions & Clean Up?")
        konfirmasi.informativeText = teks(
            "Ini akan menghapus Launch at Login dan file /etc/sudoers.d/dontdoze agar tidak ada sisa konfigurasi jika Anda ingin menghapus DontDoze.",
            "This will remove Launch at Login and /etc/sudoers.d/dontdoze so no leftover configuration remains before deleting DontDoze."
        )
        konfirmasi.addButton(withTitle: teks("Hapus", "Remove"))
        konfirmasi.addButton(withTitle: teks("Batal", "Cancel"))
        guard konfirmasi.runModal() == .alertFirstButtonReturn else { return }

        lanjutinAplikasiKeSuspend()
        matiinCaffeinate()
        if cekSleepDisabled(di: bacaOutputPmset()) {
            _ = jalaninPmsetAdmin("disablesleep 0")
            cacheSleepDimatiin = false
        }
        #if arch(x86_64)
        if cekTurboBoostMati() {
            _ = setTurboBoostMati(false, tampilinAlert: false)
        }
        #endif
        try? FileManager.default.removeItem(at: urlLaunchAgent)

        let pathSudoers = "/etc/sudoers.d/dontdoze"
        if FileManager.default.fileExists(atPath: pathSudoers) {
            let skrip = "do shell script \"/bin/rm -f \(pathSudoers)\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: skrip)?.executeAndReturnError(&error)
        }

        let selesai = NSAlert()
        selesai.messageText = teks("Selesai Dibersihkan", "Cleanup Complete")
        selesai.informativeText = teks(
            "Semua izin dan konfigurasi sudah dihapus. Anda sekarang bisa memindahkan DontDoze.app ke Trash.",
            "All permissions and configurations have been removed. You can now safely move DontDoze.app to Trash."
        )
        selesai.runModal()
    }

    func pastiinSudoersSiap() -> Bool {
        if FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
            return true
        }
        return pasangFileSudoers()
    }

    func pasangFileSudoers() -> Bool {
        let pathSudoers = "/etc/sudoers.d/dontdoze"
        let user = NSUserName()
        let aturan = "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a *, /sbin/kextload *, /sbin/kextunload *, /usr/sbin/chown -R root\\:wheel *\n"
        let pathSementara = "/tmp/dontdoze_sudoers"
        do {
            try aturan.write(toFile: pathSementara, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        let perintahSetup = "/bin/cp \(pathSementara) \(pathSudoers) && /bin/chmod 0440 \(pathSudoers) && /usr/sbin/visudo -cf \(pathSudoers) && /bin/rm -f \(pathSementara)"
        let skrip = "do shell script \"\(perintahSetup)\" with administrator privileges"
        var error: NSDictionary?
        if let script = NSAppleScript(source: skrip) {
            script.executeAndReturnError(&error)
            if let err = error {
                let alert = NSAlert()
                alert.messageText = "Setup Izin Gagal"
                alert.informativeText = (err[NSAppleScript.errorMessage] as? String) ?? "Gagal membuat aturan sudoers."
                alert.alertStyle = .warning
                alert.runModal()
                return false
            }
            return true
        }
        return false
    }

    func jalaninPerintahSudo(_ perintah: String, tampilinAlertError: Bool = true) -> Bool {
        let pathSudoers = "/etc/sudoers.d/dontdoze"
        if !FileManager.default.fileExists(atPath: pathSudoers) {
            let alert = NSAlert()
            alert.messageText = teks("Izin Sistem Diperlukan", "System Permission Required")
            alert.informativeText = teks(
                "Fitur ini memerlukan izin sistem (pmset / Turbo Boost). Pasang Helper di /etc/sudoers.d/dontdoze agar tidak perlu password lagi (hanya mengizinkan perintah daya & kext, bukan akses admin penuh), atau lanjutkan sekali ini dengan password?",
                "This feature requires system permission (pmset / Turbo Boost). Install Helper at /etc/sudoers.d/dontdoze to skip future password prompts (only allows power & kext commands, not full admin access), or continue once with a password?"
            )
            alert.addButton(withTitle: teks("Pasang Izin", "Install"))
            alert.addButton(withTitle: teks("Pakai Password Saja", "Use Password Only"))
            alert.addButton(withTitle: teks("Batal", "Cancel"))
            let respon = alert.runModal()
            if respon == .alertThirdButtonReturn {
                return false
            } else if respon == .alertSecondButtonReturn {
                let skrip = "do shell script \"\(perintah)\" with administrator privileges"
                var error: NSDictionary?
                NSAppleScript(source: skrip)?.executeAndReturnError(&error)
                if let err = error, tampilinAlertError {
                    let errAlert = NSAlert()
                    errAlert.messageText = teks("Gagal Menjalankan Perintah", "Command Failed")
                    errAlert.informativeText = (err[NSAppleScript.errorMessage] as? String) ?? ""
                    errAlert.alertStyle = .warning
                    errAlert.runModal()
                }
                return error == nil
            } else {
                guard pasangFileSudoers() else { return false }
            }
        }

        let proses = Process()
        proses.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proses.arguments = ["-c", "sudo -n \(perintah)"]
        let pipa = Pipe()
        proses.standardError = pipa
        try? proses.run()
        proses.waitUntilExit()
        if proses.terminationStatus != 0 && tampilinAlertError {
            let data = pipa.fileHandleForReading.readDataToEndOfFile()
            let pesanErr = String(data: data, encoding: .utf8) ?? "Terjadi kesalahan."
            let alert = NSAlert()
            alert.messageText = "Gagal Menjalankan Perintah"
            alert.informativeText = pesanErr
            alert.alertStyle = .warning
            alert.runModal()
        }
        return proses.terminationStatus == 0
    }

    func jalaninPmsetAdmin(_ args: String) -> Bool {
        jalaninPerintahSudo("/usr/bin/pmset -a \(args)", tampilinAlertError: false)
    }

    func cekLaunchPasLogin() -> Bool {
        FileManager.default.fileExists(atPath: urlLaunchAgent.path)
    }

    @objc func toggleLaunchPasLogin() {
        let fm = FileManager.default
        if cekLaunchPasLogin() {
            try? fm.removeItem(at: urlLaunchAgent)
        } else {
            guard let pathEksekusi = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": labelLaunchAgent,
                "ProgramArguments": [pathEksekusi],
                "RunAtLoad": true
            ]
            let dir = urlLaunchAgent.deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: urlLaunchAgent, atomically: true)
        }
    }
}
