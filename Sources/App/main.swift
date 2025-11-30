import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy before creating status bar item
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set menu bar icon (using system symbol)
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Menu Bar App")
            button.image?.isTemplate = true
        }

        // Create menu
        let menu = NSMenu()
        let helloMenuItem = NSMenuItem(title: "Hello", action: #selector(helloMenuItemClicked), keyEquivalent: "")
        helloMenuItem.target = self
        menu.addItem(helloMenuItem)
        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusBarItem?.menu = menu
    }

    @objc func helloMenuItemClicked() {
        let alert = NSAlert()
        alert.messageText = "Hello!"
        alert.informativeText = "Hello from the menu bar!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

