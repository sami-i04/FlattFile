import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PDFKit
import Quartz
import CoreImage
import Compression

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "FlattFile"
        let root = NSView()
        let left = PaneContainer(hosting(LeftPane(model: model)))
        let right = PaneContainer(hosting(SettingsPanel(model: model)))
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        [left, line, right].forEach(root.addSubview)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.topAnchor.constraint(equalTo: root.topAnchor),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            line.topAnchor.constraint(equalTo: root.topAnchor),
            line.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            line.widthAnchor.constraint(equalToConstant: 1),
            right.leadingAnchor.constraint(equalTo: line.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            right.topAnchor.constraint(equalTo: root.topAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            right.widthAnchor.constraint(equalToConstant: 280),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 820),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 560),
        ])
        window.contentView = root
        window.setContentSize(NSSize(width: 960, height: 640))
        window.contentMinSize = NSSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("FlattFileMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) { model.add(urls) }

    @objc func openFiles() { model.openPanel() }
    @objc func compress() { model.compressAll() }

    func buildMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem]) {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.submenu = m
            main.addItem(it)
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        sub("FlattFile", [
            item(String(localized: "Über FlattFile"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item(String(localized: "FlattFile ausblenden"), #selector(NSApplication.hide(_:)), "h"),
            item(String(localized: "Andere ausblenden"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(String(localized: "Alle einblenden"), #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item(String(localized: "FlattFile beenden"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        sub(String(localized: "Ablage"), [
            item(String(localized: "Dateien hinzufügen…"), #selector(openFiles), "o", target: self),
            item(String(localized: "Komprimieren"), #selector(compress), "\r", target: self),
            .separator(),
            item(String(localized: "Fenster schließen"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        sub(String(localized: "Bearbeiten"), [
            item(String(localized: "Widerrufen"), Selector(("undo:")), "z"),
            item(String(localized: "Wiederholen"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(String(localized: "Ausschneiden"), #selector(NSText.cut(_:)), "x"),
            item(String(localized: "Kopieren"), #selector(NSText.copy(_:)), "c"),
            item(String(localized: "Einsetzen"), #selector(NSText.paste(_:)), "v"),
            item(String(localized: "Alles auswählen"), #selector(NSText.selectAll(_:)), "a"),
        ])
        let win: [NSMenuItem] = [
            item(String(localized: "Im Dock ablegen"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(String(localized: "Zoomen"), #selector(NSWindow.performZoom(_:)), ""),
        ]
        sub(String(localized: "Fenster"), win)
        NSApp.windowsMenu = main.items.last?.submenu
        NSApp.mainMenu = main
    }
}
