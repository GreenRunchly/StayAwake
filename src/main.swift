import Cocoa

enum AppLanguage: String {
    case system
    case id
    case en
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var caffeinateProcess: Process?
    private var isActive = false
    private var cachedSleepDisabled = false
    private var cachedTurboBoostDisabled = false
    private let languageKey = "AppLanguage"

    private var selectedLanguage: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: languageKey) ?? AppLanguage.system.rawValue
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
        }
    }

    private var effectiveLanguage: AppLanguage {
        switch selectedLanguage {
        case .system:
            return (Locale.preferredLanguages.first?.hasPrefix("id") == true) ? .id : .en
        case .id, .en:
            return selectedLanguage
        }
    }

    private func t(_ idText: String, _ enText: String) -> String {
        effectiveLanguage == .id ? idText : enText
    }

    private let launchAgentLabel = "com.rizki.StayAwake"
    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Sync initial state with current pmset SleepDisabled
        cachedSleepDisabled = isSleepDisabledInSystem()
        if cachedSleepDisabled {
            startCaffeinate()
            isActive = true
        }
        updateIcon()
        DispatchQueue.global(qos: .utility).async {
            let turbo = self.isTurboBoostDisabled()
            DispatchQueue.main.async {
                self.cachedTurboBoostDisabled = turbo
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopCaffeinate()
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            showMenu()
        } else {
            toggleMode()
        }
    }

    @objc private func toggleMode() {
        if isActive {
            stopCaffeinate()
            isActive = false
        } else {
            startCaffeinate()
            isActive = true
        }
        updateIcon()
    }

    @objc private func toggleSystemSleepDisabled() {
        let target = cachedSleepDisabled ? "disablesleep 0" : "disablesleep 1"
        if runAdminPmset(target) {
            cachedSleepDisabled.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let statusTitle = isActive
            ? t("Perangkat tetap terjaga", "Device will stay awake")
            : t("Perangkat bisa tidur", "Device can go to sleep")
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let toggleTitle = isActive
            ? t("Matikan Mode Terjaga", "Allow Sleep (Turn Off)")
            : t("Jaga Tetap Menyala", "Keep Device Awake")
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleMode), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let sleepDisabledItem = NSMenuItem(title: t("Cegah Tidur saat Layar Ditutup", "Prevent Sleep on Lid Close"), action: #selector(toggleSystemSleepDisabled), keyEquivalent: "")
        sleepDisabledItem.target = self
        sleepDisabledItem.state = cachedSleepDisabled ? .on : .off
        menu.addItem(sleepDisabledItem)

        #if arch(x86_64)
        let turboItem = NSMenuItem(title: t("Matikan Turbo Boost (Lebih Adem)", "Disable Turbo Boost (Cooler)"), action: #selector(toggleTurboBoost), keyEquivalent: "")
        turboItem.target = self
        turboItem.state = cachedTurboBoostDisabled ? .on : .off
        menu.addItem(turboItem)
        #endif

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: t("Buka Otomatis saat Login", "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        let langMenu = NSMenu()
        let langOptions: [(String, AppLanguage)] = [
            (t("Ikuti Sistem", "Follow System"), .system),
            ("Indonesia", .id),
            ("English", .en)
        ]
        for (title, lang) in langOptions {
            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (selectedLanguage == lang) ? .on : .off
            langMenu.addItem(item)
        }
        let hasSudoers = FileManager.default.fileExists(atPath: "/etc/sudoers.d/stayawake")
        let permTitle = hasSudoers
            ? t("Hapus Izin Sistem...", "Remove System Permissions...")
            : t("Pasang Izin Sistem...", "Install System Permissions...")
        let permAction = hasSudoers ? #selector(uninstallPermissions) : #selector(installPermissions)
        let permItem = NSMenuItem(title: permTitle, action: permAction, keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        let langParent = NSMenuItem(title: t("Bahasa", "Language"), action: nil, keyEquivalent: "")
        langParent.submenu = langMenu
        menu.addItem(langParent)

        let quitItem = NSMenuItem(title: t("Keluar", "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) else { return }
        selectedLanguage = lang
        updateIcon()
    }

    @objc private func quitApp() {
        stopCaffeinate()
        NSApp.terminate(nil)
    }

    @objc private func installPermissions() {
        _ = ensureSudoersSetup()
    }

    @objc private func uninstallPermissions() {
        let confirm = NSAlert()
        confirm.messageText = t("Hapus Izin & Bersihkan?", "Remove Permissions & Clean Up?")
        confirm.informativeText = t(
            "Ini akan menghapus Launch at Login dan file /etc/sudoers.d/stayawake agar tidak ada sisa konfigurasi jika Anda ingin menghapus StayAwake.",
            "This will remove Launch at Login and /etc/sudoers.d/stayawake so no leftover configuration remains before deleting StayAwake."
        )
        confirm.addButton(withTitle: t("Hapus", "Remove"))
        confirm.addButton(withTitle: t("Batal", "Cancel"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        stopCaffeinate()
        try? FileManager.default.removeItem(at: launchAgentURL)

        let sudoersPath = "/etc/sudoers.d/stayawake"
        if FileManager.default.fileExists(atPath: sudoersPath) {
            let scriptSource = "do shell script \"/bin/rm -f \(sudoersPath)\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)
        }

        let done = NSAlert()
        done.messageText = t("Selesai Dibersihkan", "Cleanup Complete")
        done.informativeText = t(
            "Semua izin dan konfigurasi sudah dihapus. Anda sekarang bisa memindahkan StayAwake.app ke Trash.",
            "All permissions and configurations have been removed. You can now safely move StayAwake.app to Trash."
        )
        done.runModal()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "zzz", accessibilityDescription: "StayAwake") {
            image.isTemplate = true
            button.image = image
            button.appearsDisabled = !isActive
        } else {
            button.title = isActive ? "Zzz" : "zzz"
        }
        button.toolTip = isActive
            ? "StayAwake: ON (Klik untuk matikan, klik kanan untuk menu)"
            : "StayAwake: OFF (Klik untuk nyalakan, klik kanan untuk menu)"
    }

    private func startCaffeinate() {
        guard caffeinateProcess == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-i", "-m", "-s"]
        try? process.run()
        caffeinateProcess = process
    }

    private func stopCaffeinate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    private func isSleepDisabledInSystem() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains("SleepDisabled\t\t1") || output.contains("SleepDisabled 1")
    }

    private func ensureSudoersSetup() -> Bool {
        if FileManager.default.fileExists(atPath: "/etc/sudoers.d/stayawake") {
            return true
        }
        return installSudoersFile()
    }

    private func installSudoersFile() -> Bool {
        let sudoersPath = "/etc/sudoers.d/stayawake"
        let user = NSUserName()
        let rule = "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *, /sbin/kextload *, /sbin/kextunload *, /usr/sbin/chown -R root\\:wheel *\n"
        let tmpPath = "/tmp/stayawake_sudoers"
        do {
            try rule.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        let setupCmd = "/bin/cp \(tmpPath) \(sudoersPath) && /bin/chmod 0440 \(sudoersPath) && /usr/sbin/visudo -cf \(sudoersPath) && /bin/rm -f \(tmpPath)"
        let scriptSource = "do shell script \"\(setupCmd)\" with administrator privileges"
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
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

    private func runSudoCommand(_ command: String, showAlertOnError: Bool = true) -> Bool {
        let sudoersPath = "/etc/sudoers.d/stayawake"
        if !FileManager.default.fileExists(atPath: sudoersPath) {
            let alert = NSAlert()
            alert.messageText = t("Izin Sistem Diperlukan", "System Permission Required")
            alert.informativeText = t(
                "File izin (/etc/sudoers.d/stayawake) belum terpasang. Pasang sekali agar tidak perlu memasukkan password lagi, atau lanjutkan sekali ini dengan password?",
                "Permission file (/etc/sudoers.d/stayawake) is not installed. Install it once to skip future password prompts, or continue this time with a password?"
            )
            alert.addButton(withTitle: t("Pasang Izin", "Install"))
            alert.addButton(withTitle: t("Pakai Password Saja", "Use Password Only"))
            alert.addButton(withTitle: t("Batal", "Cancel"))
            let response = alert.runModal()
            if response == .alertThirdButtonReturn {
                return false
            } else if response == .alertSecondButtonReturn {
                let scriptSource = "do shell script \"\(command)\" with administrator privileges"
                var error: NSDictionary?
                NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)
                if let err = error, showAlertOnError {
                    let errAlert = NSAlert()
                    errAlert.messageText = t("Gagal Menjalankan Perintah", "Command Failed")
                    errAlert.informativeText = (err[NSAppleScript.errorMessage] as? String) ?? ""
                    errAlert.alertStyle = .warning
                    errAlert.runModal()
                }
                return error == nil
            } else {
                guard installSudoersFile() else { return false }
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "sudo -n \(command)"]
        let pipe = Pipe()
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 && showAlertOnError {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: data, encoding: .utf8) ?? "Terjadi kesalahan."
            let alert = NSAlert()
            alert.messageText = "Gagal Menjalankan Perintah"
            alert.informativeText = errMsg
            alert.alertStyle = .warning
            alert.runModal()
        }
        return process.terminationStatus == 0
    }

    private func runAdminPmset(_ args: String) -> Bool {
        runSudoCommand("/usr/bin/pmset -a \(args)", showAlertOnError: false)
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    @objc private func toggleLaunchAtLogin() {
        let fm = FileManager.default
        if isLaunchAtLoginEnabled() {
            try? fm.removeItem(at: launchAgentURL)
        } else {
            guard let execPath = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": launchAgentLabel,
                "ProgramArguments": [execPath],
                "RunAtLoad": true
            ]
            let dir = launchAgentURL.deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            (plist as NSDictionary).write(to: launchAgentURL, atomically: true)
        }
    }

    private func findTurboBoostKextPath() -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("DisableTurboBoost.64bits.kext").path {
            candidates.append(bundled)
        }
        candidates.append(contentsOf: [
            "/Applications/Turbo Boost Switcher.app/Contents/Resources/DisableTurboBoost.64bits.kext",
            "/Applications/Turbo Boost Switcher Pro.app/Contents/Resources/DisableTurboBoost.64bits.kext"
        ])
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func isTurboBoostDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains("DisableTurboBoost")
    }

    @objc private func toggleTurboBoost() {
        guard let kextPath = findTurboBoostKextPath() else {
            let alert = NSAlert()
            alert.messageText = "Turbo Boost Switcher Belum Terpasang"
            alert.informativeText = "macOS tidak memiliki perintah bawaan untuk mematikan Turbo Boost. Pasang aplikasi Turbo Boost Switcher di folder Applications agar StayAwake dapat menggunakan kernel extension-nya."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        if cachedTurboBoostDisabled {
            if runSudoCommand("/sbin/kextunload '\(kextPath)'") {
                cachedTurboBoostDisabled = false
            }
        } else {
            if runSudoCommand("/usr/sbin/chown -R root:wheel '\(kextPath)'") &&
               runSudoCommand("/sbin/kextload '\(kextPath)'") {
                cachedTurboBoostDisabled = true
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
