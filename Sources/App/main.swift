import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var puzzleMenuItemView: PuzzleMenuItemView?
    var puzzleMenuItem: NSMenuItem?
    var statsWindowController: StatsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy before creating status bar item
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set menu bar icon (using chess knight symbol)
        if let button = statusBarItem?.button {
            // Create a larger icon from the Unicode chess knight character
            let iconSize: CGFloat = 22
            let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
            image.lockFocus()

            // Draw the chess knight character at a larger size
            let font = NSFont.systemFont(ofSize: iconSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
            let attributedString = NSAttributedString(string: "♞", attributes: attributes)
            let stringSize = attributedString.size()
            let point = NSPoint(
                x: (iconSize - stringSize.width) / 2,
                y: (iconSize - stringSize.height) / 2 - 1 // Slight vertical adjustment
            )
            attributedString.draw(at: point)

            image.unlockFocus()
            image.isTemplate = true

            button.image = image
            button.imagePosition = .imageLeading
            button.title = ""
        }

        // Load puzzles
        PuzzleManager.shared.loadPuzzles()

        // Check if we need to refresh database
        checkAndRefreshDatabaseIfNeeded()

        // Create menu
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Create puzzle view menu item
        let puzzleView = PuzzleMenuItemView(frame: .zero)
        puzzleMenuItemView = puzzleView

        let puzzleMenuItem = NSMenuItem()
        puzzleMenuItem.view = puzzleView
        menu.addItem(puzzleMenuItem)
        self.puzzleMenuItem = puzzleMenuItem

        menu.addItem(NSMenuItem.separator())

        // New Puzzle
        let newPuzzleItem = NSMenuItem(title: "New Puzzle", action: #selector(newPuzzleClicked), keyEquivalent: "n")
        newPuzzleItem.target = self
        menu.addItem(newPuzzleItem)

        menu.addItem(NSMenuItem.separator())

        // Difficulty submenu
        let difficultyItem = NSMenuItem(title: "Difficulty", action: nil, keyEquivalent: "")
        let difficultySubmenu = NSMenu()

        for difficulty in Difficulty.allCases {
            let item = NSMenuItem(title: difficulty.rawValue, action: #selector(difficultySelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = difficulty
            if difficulty == PuzzleManager.shared.getDifficulty() {
                item.state = .on
            }
            difficultySubmenu.addItem(item)
        }

        difficultyItem.submenu = difficultySubmenu
        menu.addItem(difficultyItem)

        menu.addItem(NSMenuItem.separator())

        // Statistics
        let statsItem = NSMenuItem(title: "Statistics", action: #selector(showStatistics), keyEquivalent: "s")
        statsItem.target = self
        menu.addItem(statsItem)

        // Refresh Database
        let refreshItem = NSMenuItem(title: "Refresh Puzzle Database", action: #selector(refreshDatabase), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusBarItem?.menu = menu
    }

    @objc func newPuzzleClicked() {
        puzzleMenuItemView?.loadNewPuzzle()
    }

    @objc func difficultySelected(_ sender: NSMenuItem) {
        guard let difficulty = sender.representedObject as? Difficulty else { return }
        PuzzleManager.shared.setDifficulty(difficulty)

        // Update menu state
        if let difficultyMenu = statusBarItem?.menu?.item(withTitle: "Difficulty")?.submenu {
            for item in difficultyMenu.items {
                item.state = (item.representedObject as? Difficulty == difficulty) ? .on : .off
            }
        }

        // Reload puzzle if view exists
        puzzleMenuItemView?.loadNewPuzzle()
    }

    @objc func showStatistics() {
        if statsWindowController == nil {
            let windowController = StatsWindowController()
            statsWindowController = windowController
        }
        statsWindowController?.showWindow(nil)
        statsWindowController?.updateStats()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refreshDatabase() {
        downloadDatabase()
    }

    private func checkAndRefreshDatabaseIfNeeded() {
        // Check if we have any cached puzzles
        if DatabaseDownloader.shared.loadCachedPuzzles() == nil {
            print("[DEBUG] No cached puzzles found, starting automatic download...")
            // No cached puzzles, download automatically without confirmation
            downloadDatabase()
        } else if DatabaseDownloader.shared.needsRefresh() {
            print("[DEBUG] Database needs refresh (older than 7 days), starting automatic download...")
            downloadDatabase()
        }
    }

    private func downloadDatabase() {
        // Activate app to show dialogs
        NSApp.activate(ignoringOtherApps: true)

        // Create a window for the progress dialog
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Downloading Puzzles"
        window.center()
        window.isReleasedWhenClosed = false

        let progressView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 120))

        let titleLabel = NSTextField(labelWithString: "Downloading puzzle database...")
        titleLabel.frame = NSRect(x: 20, y: 80, width: 410, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        progressView.addSubview(titleLabel)

        let progressIndicator = NSProgressIndicator(frame: NSRect(x: 20, y: 45, width: 410, height: 20))
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressView.addSubview(progressIndicator)

        let statusLabel = NSTextField(labelWithString: "Starting download...")
        statusLabel.frame = NSRect(x: 20, y: 15, width: 410, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        progressView.addSubview(statusLabel)

        window.contentView = progressView
        window.makeKeyAndOrderFront(nil)

        // Start download in background
        DispatchQueue.global(qos: .userInitiated).async {
            DatabaseDownloader.shared.downloadDatabase(
                progress: { downloaded, total in
                    DispatchQueue.main.async {
                        let downloadedMB = Double(downloaded) / 1_000_000
                        let totalMB = Double(total) / 1_000_000
                        let percent = total > 0 ? (Double(downloaded) / Double(total)) * 100 : 0

                        statusLabel.stringValue = String(format: "Downloaded: %.1f MB / %.1f MB (%.1f%%)", downloadedMB, totalMB, percent)
                        progressIndicator.doubleValue = percent
                        window.displayIfNeeded()
                    }
                },
                completion: { result in
                    DispatchQueue.main.async {
                        window.close()

                        switch result {
                        case .success(let puzzles):
                            PuzzleManager.shared.setPuzzles(puzzles)
                            print("[DEBUG] Successfully loaded \(puzzles.count) puzzles")
                            let successAlert = NSAlert()
                            successAlert.messageText = "Download Complete"
                            successAlert.informativeText = "Downloaded \(puzzles.count) puzzles successfully!"
                            successAlert.alertStyle = .informational
                            successAlert.addButton(withTitle: "OK")
                            NSApp.activate(ignoringOtherApps: true)
                            successAlert.runModal()
                        case .failure(let error):
                            print("[DEBUG] Download failed: \(error.localizedDescription)")
                            let errorAlert = NSAlert(error: error)
                            errorAlert.informativeText = error.localizedDescription + "\n\nCheck console for debug output."
                            NSApp.activate(ignoringOtherApps: true)
                            errorAlert.runModal()
                        }
                    }
                }
            )
        }
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

