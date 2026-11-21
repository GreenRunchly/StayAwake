import Cocoa
import Darwin
import IOKit

extension AppDelegate {
    @objc func pilihModeSuspendAplikasi(_ sender: NSMenuItem) {
        guard let mauSuspend = sender.representedObject as? Bool else { return }
        suspendPasTutupLayar = mauSuspend
        if mauSuspend {
            pastiinCegahSleepNyala()
        } else {
            lanjutinAplikasiKeSuspend()
        }
        aturPantauTutupLayar()
    }

    var butuhPantauTutupLayar: Bool {
        let butuhSafetyNet = cacheSleepDimatiin || (!modeLanjutan && lagiTerjaga) || suspendPasTutupLayar
        #if arch(x86_64)
        return butuhSafetyNet || modeTurboBoost == .matiPasTutupLayar
        #else
        return butuhSafetyNet
        #endif
    }

    func aturPantauTutupLayar() {
        timerPantauLayar?.invalidate()
        timerPantauLayar = nil
        if butuhPantauTutupLayar {
            statusTerakhirLayarTutup = lagiTutupLayar()
            let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.cekKondisiTutupLayar()
            }
            RunLoop.main.add(timer, forMode: .common)
            timerPantauLayar = timer
        } else {
            statusTerakhirLayarTutup = false
            lanjutinAplikasiKeSuspend()
        }
    }

    func cekKondisiTutupLayar() {
        let lagiTutup = lagiTutupLayar()
        guard lagiTutup != statusTerakhirLayarTutup else { return }
        statusTerakhirLayarTutup = lagiTutup
        if lagiTutup {
            let harusTetapNyala = cacheSleepDimatiin || (!modeLanjutan && lagiTerjaga) || suspendPasTutupLayar
            if harusTetapNyala && FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") && !cekSleepDisabled(di: bacaOutputPmset()) {
                if jalaninPmsetAdmin("disablesleep 1") {
                    cacheSleepDimatiin = true
                    updateIkon()
                    tulisLogSuspend("SAFETY NET: Re-enabled SleepDisabled=1 on lid close")
                }
            }
            if suspendPasTutupLayar && cacheSleepDimatiin {
                suspendAplikasiJalan()
            }
            #if arch(x86_64)
            if modeTurboBoost == .matiPasTutupLayar && !cacheTurboMati && FileManager.default.fileExists(atPath: "/etc/sudoers.d/dontdoze") {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self = self else { return }
                    if self.setTurboBoostMati(true, tampilinAlert: false) {
                        DispatchQueue.main.async {
                            self.turboDimatiinKarenaTutupLayar = true
                        }
                        self.tulisLogSuspend("TURBO BOOST: Disabled on lid close")
                    }
                }
            }
            #endif
        } else {
            lanjutinAplikasiKeSuspend()
        }
    }

    func lagiTutupLayar() -> Bool {
        let layanan = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard layanan != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(layanan) }
        if let nilai = IORegistryEntryCreateCFProperty(layanan, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return nilai
        }
        return false
    }

    func suspendAplikasiJalan() {
        let pidSendiri = ProcessInfo.processInfo.processIdentifier
        let pidCaffeinate = prosesCaffeinate?.processIdentifier
        let targetAplikasi = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier &&
            app.bundleIdentifier != "com.apple.finder" &&
            app.processIdentifier > 0 &&
            app.processIdentifier != pidSendiri
        }
        guard !targetAplikasi.isEmpty else { return }

        let prefixBundle = targetAplikasi.compactMap { $0.bundleURL?.path }.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var daftarPIDTarget = Set(targetAplikasi.map { $0.processIdentifier })

        let proses = Process()
        proses.executableURL = URL(fileURLWithPath: "/bin/ps")
        proses.arguments = ["-u", "\(getuid())", "-o", "pid=,ppid=,comm="]
        let pipa = Pipe()
        proses.standardOutput = pipa
        try? proses.run()
        proses.waitUntilExit()

        var anakPerInduk: [pid_t: [pid_t]] = [:]
        if let output = String(data: pipa.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            for baris in output.split(separator: "\n") {
                let rapi = baris.drop(while: { $0.isWhitespace })
                let bagian = rapi.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
                guard bagian.count >= 2, let pid = pid_t(bagian[0]), let ppid = pid_t(bagian[1]) else { continue }
                anakPerInduk[ppid, default: []].append(pid)
                if bagian.count == 3, !daftarPIDTarget.contains(pid) {
                    let pathEksekusi = String(bagian[2])
                    if prefixBundle.contains(where: { pathEksekusi.hasPrefix($0) }) {
                        daftarPIDTarget.insert(pid)
                    }
                }
            }
        }

        var antrean = Array(daftarPIDTarget)
        while let sekarang = antrean.popLast() {
            for anak in anakPerInduk[sekarang] ?? [] where !daftarPIDTarget.contains(anak) {
                daftarPIDTarget.insert(anak)
                antrean.append(anak)
            }
        }

        daftarPIDTarget.remove(pidSendiri)
        if let pidCaf = pidCaffeinate {
            daftarPIDTarget.remove(pidCaf)
        }

        var jumlahKesuspend = 0
        for pid in daftarPIDTarget {
            if kill(pid, SIGSTOP) == 0 {
                daftarPIDKeSuspend.insert(pid)
                jumlahKesuspend += 1
            }
        }
        UserDefaults.standard.set(Array(daftarPIDKeSuspend.map { Int($0) }), forKey: keySisaPIDKeSuspend)
        let namaAplikasi = targetAplikasi.compactMap { $0.localizedName }.sorted().joined(separator: ", ")
        tulisLogSuspend("SUSPENDED (lid closed): \(targetAplikasi.count) apps, \(jumlahKesuspend) PIDs [\(namaAplikasi)]")
    }

    func lanjutinAplikasiKeSuspend() {
        if !daftarPIDKeSuspend.isEmpty {
            let jumlah = daftarPIDKeSuspend.count
            for pid in daftarPIDKeSuspend {
                _ = kill(pid, SIGCONT)
            }
            daftarPIDKeSuspend.removeAll()
            UserDefaults.standard.removeObject(forKey: keySisaPIDKeSuspend)
            tulisLogSuspend("RESUMED: \(jumlah) PIDs")
        }
        balikinTurboBoostKalauPerlu()
    }

    func pulihinSisaAplikasiKeSuspend() {
        guard let tersimpan = UserDefaults.standard.array(forKey: keySisaPIDKeSuspend) as? [Int], !tersimpan.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: keySisaPIDKeSuspend)
        let daftarPID = tersimpan.filter { $0 > 0 }.map(String.init).joined(separator: ",")
        guard !daftarPID.isEmpty else { return }

        let proses = Process()
        proses.executableURL = URL(fileURLWithPath: "/bin/ps")
        proses.arguments = ["-p", daftarPID, "-o", "pid=,state="]
        let pipa = Pipe()
        proses.standardOutput = pipa
        try? proses.run()
        proses.waitUntilExit()

        var kepulihkan = 0
        if let output = String(data: pipa.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            for baris in output.split(separator: "\n") {
                let bagian = baris.split(whereSeparator: { $0.isWhitespace })
                if bagian.count >= 2, let pid = pid_t(bagian[0]), bagian[1].hasPrefix("T") {
                    if kill(pid, SIGCONT) == 0 {
                        kepulihkan += 1
                    }
                }
            }
        }
        if kepulihkan > 0 {
            tulisLogSuspend("RESUMED (crash recovery): \(kepulihkan) PIDs")
        }
    }

    var urlLogSuspend: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DontDoze.log")
    }

    func tulisLogSuspend(_ pesan: String) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let baris = "[\(formatter.string(from: Date()))] \(pesan)\n"
        guard let data = baris.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: urlLogSuspend.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: urlLogSuspend.path), let handle = try? FileHandle(forWritingTo: urlLogSuspend) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: urlLogSuspend)
        }
    }

    @objc func bukaLogSuspend() {
        if !FileManager.default.fileExists(atPath: urlLogSuspend.path) {
            tulisLogSuspend("Log initialized (no apps suspended yet)")
        }
        NSWorkspace.shared.open(urlLogSuspend)
    }
}
