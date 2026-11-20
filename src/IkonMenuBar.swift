import Cocoa

extension AppDelegate {
    @objc func pilihIkonMenuBar(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let ikon = IkonMenuBar(rawValue: raw) else { return }
        ikonKepilih = ikon
        updateIkon()
    }

    func bikinIkonKopi() -> NSImage {
        let gambar = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()

            // Badan cangkir
            let cangkir = NSBezierPath()
            cangkir.lineWidth = 1.4
            cangkir.lineCapStyle = .round
            cangkir.lineJoinStyle = .round
            cangkir.move(to: NSPoint(x: 3.5, y: 10.5))
            cangkir.line(to: NSPoint(x: 13.0, y: 10.5))
            cangkir.line(to: NSPoint(x: 12.2, y: 6.2))
            cangkir.curve(to: NSPoint(x: 8.25, y: 4.0), controlPoint1: NSPoint(x: 11.8, y: 4.5), controlPoint2: NSPoint(x: 10.2, y: 4.0))
            cangkir.curve(to: NSPoint(x: 4.3, y: 6.2), controlPoint1: NSPoint(x: 6.3, y: 4.0), controlPoint2: NSPoint(x: 4.7, y: 4.5))
            cangkir.close()
            cangkir.stroke()

            // Gagang cangkir
            let gagang = NSBezierPath()
            gagang.lineWidth = 1.4
            gagang.lineCapStyle = .round
            gagang.move(to: NSPoint(x: 13.0, y: 9.7))
            gagang.curve(to: NSPoint(x: 13.0, y: 6.3), controlPoint1: NSPoint(x: 15.6, y: 9.7), controlPoint2: NSPoint(x: 15.6, y: 6.3))
            gagang.stroke()

            // Tatakan bawah
            let tatakan = NSBezierPath()
            tatakan.lineWidth = 1.4
            tatakan.lineCapStyle = .round
            tatakan.move(to: NSPoint(x: 3.0, y: 2.5))
            tatakan.line(to: NSPoint(x: 13.5, y: 2.5))
            tatakan.stroke()

            // Asap kopi
            for x in [6.0, 8.5, 11.0] {
                let asap = NSBezierPath()
                asap.lineWidth = 1.2
                asap.lineCapStyle = .round
                asap.move(to: NSPoint(x: x, y: 12.2))
                asap.curve(to: NSPoint(x: x, y: 15.8), controlPoint1: NSPoint(x: x - 0.9, y: 13.4), controlPoint2: NSPoint(x: x + 0.9, y: 14.6))
                asap.stroke()
            }
            return true
        }
        gambar.isTemplate = true
        return gambar
    }

    func bikinIkonMacBookTidur() -> NSImage? {
        guard let dasar = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "DontDoze") else { return nil }
        let ukuranKanvas = NSSize(width: dasar.size.width, height: 18)
        let posisiY = (ukuranKanvas.height - dasar.size.height) / 2.0
        let kotakLaptop = NSRect(x: 0, y: posisiY, width: dasar.size.width, height: dasar.size.height)
        let gambar = NSImage(size: ukuranKanvas, flipped: false) { _ in
            dasar.draw(in: kotakLaptop)

            if let zzz = NSImage(systemSymbolName: "zzz", accessibilityDescription: nil) {
                let skala: CGFloat = 0.78
                let ukuranZ = NSSize(width: zzz.size.width * skala, height: zzz.size.height * skala)
                let titikZ = NSPoint(
                    x: (ukuranKanvas.width - ukuranZ.width) / 2.0 + 1.5,
                    y: ukuranKanvas.height - ukuranZ.height - 0.5
                )
                let kotakZ = NSRect(origin: titikZ, size: ukuranZ)

                // Potong halo 1pt di sekitar zzz biar nggak nyaru sama bingkai laptop
                let geseran: [(CGFloat, CGFloat)] = [
                    (-1, 0), (1, 0), (0, -1), (0, 1),
                    (-0.8, -0.8), (0.8, -0.8), (-0.8, 0.8), (0.8, 0.8)
                ]
                for (dx, dy) in geseran {
                    zzz.draw(in: kotakZ.offsetBy(dx: dx, dy: dy), from: .zero, operation: .destinationOut, fraction: 1.0)
                }
                zzz.draw(in: kotakZ, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        gambar.isTemplate = true
        return gambar
    }

    func ambilIkonStatusBar(buat ikon: IkonMenuBar, lagiTidur: Bool = false) -> NSImage? {
        switch ikon {
        case .zzz:
            guard let img = NSImage(systemSymbolName: ikon.rawValue, accessibilityDescription: "DontDoze") else { return nil }
            img.isTemplate = true
            return img
        case .laptopcomputer:
            if lagiTidur, let gambarTidur = bikinIkonMacBookTidur() {
                return gambarTidur
            }
            guard let img = NSImage(systemSymbolName: ikon.rawValue, accessibilityDescription: "DontDoze") else { return nil }
            img.isTemplate = true
            return img
        case .coffee:
            return bikinIkonKopi()
        }
    }

    func updateIkon() {
        guard let tombol = statusItem.button else { return }
        if let gambar = ambilIkonStatusBar(buat: ikonKepilih, lagiTidur: !lagiTerjaga) {
            tombol.image = gambar
            tombol.appearsDisabled = (ikonKepilih == .laptopcomputer) ? false : !lagiTerjaga
        } else {
            tombol.title = lagiTerjaga ? "Zzz" : "zzz"
        }
        tombol.toolTip = statusTeks.replacingOccurrences(of: "\n", with: " ")
    }
}
