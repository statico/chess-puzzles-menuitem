import AppKit

class PuzzleWindowController: NSWindowController {
    private var puzzleManager = PuzzleManager.shared
    private var statsManager = StatsManager.shared
    private var engine: ChessEngine?
    private var startTime: Date?
    private var timer: Timer?

    var boardView: ChessBoardView!
    var statusLabel: NSTextField!
    var timerLabel: NSTextField!
    var streakLabel: NSTextField!
    var hintButton: NSButton!
    var solutionButton: NSButton!
    var nextButton: NSButton!
    var difficultyPopup: NSPopUpButton!

    private var contentView: NSView?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        setupUI()
        loadNewPuzzle()
    }

    private func setupUI() {
        guard let window = window else { return }

        window.title = "Chess Puzzle"
        window.center()

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        self.contentView = contentView

        // Create board view
        let boardSize: CGFloat = 480
        let boardView = ChessBoardView(frame: NSRect(x: 60, y: 180, width: boardSize, height: boardSize))
        boardView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        boardView.delegate = self
        contentView.addSubview(boardView)
        self.boardView = boardView

        // Status label
        let statusLabel = NSTextField(labelWithString: "White to move")
        statusLabel.frame = NSRect(x: 60, y: 150, width: 200, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        contentView.addSubview(statusLabel)
        self.statusLabel = statusLabel

        // Timer label
        let timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.frame = NSRect(x: 340, y: 150, width: 200, height: 20)
        timerLabel.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        timerLabel.alignment = .right
        contentView.addSubview(timerLabel)
        self.timerLabel = timerLabel

        // Streak label
        let streakLabel = NSTextField(labelWithString: "Streak: 0")
        streakLabel.frame = NSRect(x: 60, y: 120, width: 200, height: 20)
        streakLabel.font = NSFont.systemFont(ofSize: 14)
        contentView.addSubview(streakLabel)
        self.streakLabel = streakLabel

        // Difficulty popup
        let difficultyPopup = NSPopUpButton(frame: NSRect(x: 340, y: 120, width: 200, height: 24))
        difficultyPopup.addItems(withTitles: Difficulty.allCases.map { $0.rawValue })
        difficultyPopup.target = self
        difficultyPopup.action = #selector(difficultyChanged(_:))
        contentView.addSubview(difficultyPopup)
        self.difficultyPopup = difficultyPopup
        updateDifficultySelection()

        // Hint button
        let hintButton = NSButton(title: "Hint", target: self, action: #selector(hintClicked(_:)))
        hintButton.frame = NSRect(x: 60, y: 80, width: 100, height: 32)
        hintButton.bezelStyle = .rounded
        contentView.addSubview(hintButton)
        self.hintButton = hintButton

        // Solution button
        let solutionButton = NSButton(title: "Solution", target: self, action: #selector(solutionClicked(_:)))
        solutionButton.frame = NSRect(x: 170, y: 80, width: 100, height: 32)
        solutionButton.bezelStyle = .rounded
        contentView.addSubview(solutionButton)
        self.solutionButton = solutionButton

        // Next button (initially hidden)
        let nextButton = NSButton(title: "Next", target: self, action: #selector(nextClicked(_:)))
        nextButton.frame = NSRect(x: 280, y: 80, width: 100, height: 32)
        nextButton.bezelStyle = .rounded
        nextButton.isHidden = true
        contentView.addSubview(nextButton)
        self.nextButton = nextButton

        updateStats()
    }

    private func updateDifficultySelection() {
        let currentDifficulty = puzzleManager.getDifficulty()
        if let index = Difficulty.allCases.firstIndex(of: currentDifficulty) {
            difficultyPopup.selectItem(at: index)
        }
    }

    @objc private func difficultyChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard selectedIndex >= 0 && selectedIndex < Difficulty.allCases.count else { return }
        let difficulty = Difficulty.allCases[selectedIndex]
        puzzleManager.setDifficulty(difficulty)
        loadNewPuzzle()
    }

    func loadNewPuzzle() {
        guard let puzzle = puzzleManager.getNextPuzzle() else {
            showAlert(title: "No Puzzles", message: "No puzzles available. Please download the puzzle database.")
            return
        }

        engine = ChessEngine(fen: puzzle.fen)
        boardView.setEngine(engine!)

        // Set the player's color so they can only move their pieces
        if let playerColor = puzzleManager.getPlayerColor() {
            boardView.playerColor = playerColor
        }

        updateStatusLabel()
        startTimer()
        nextButton.isHidden = true
        hintButton.isEnabled = true
        solutionButton.isEnabled = true

        boardView.clearSelection()
    }

    private func updateStatusLabel() {
        guard let engine = engine else { return }
        if puzzleManager.isPlayerTurn() {
            let playerColor = puzzleManager.getPlayerColor()
            let colorName = playerColor == .white ? "White" : "Black"
            statusLabel.stringValue = "Your turn (\(colorName))"
        } else {
            let engineColor = engine.getActiveColor() == .white ? "White" : "Black"
            statusLabel.stringValue = "Engine thinking (\(engineColor))..."
        }
    }

    private func startTimer() {
        stopTimer()
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
        updateTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTimer() {
        guard let startTime = startTime else {
            timerLabel.stringValue = "00:00"
            return
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        timerLabel.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }

    private func updateStats() {
        let stats = statsManager.getStats()
        streakLabel.stringValue = "Streak: \(stats.currentStreak)"
    }

    @objc private func hintClicked(_ sender: NSButton) {
        guard let hint = puzzleManager.getHint() else { return }
        showAlert(title: "Hint", message: "First move: \(hint)")
    }

    @objc private func solutionClicked(_ sender: NSButton) {
        let solution = puzzleManager.getSolution()
        let solutionText = solution.joined(separator: " ")
        showAlert(title: "Solution", message: solutionText)
        showSolution()
    }

    private func showSolution() {
        stopTimer()
        nextButton.isHidden = false
        hintButton.isEnabled = false
        solutionButton.isEnabled = false

        // Animate solution moves
        animateSolution()
    }

    private func animateSolution() {
        guard let engine = engine else { return }
        let solution = puzzleManager.getSolution()

        var moveIndex = 0
        func makeNextMove() {
            guard moveIndex < solution.count else { return }
            let moveUCI = solution[moveIndex]
            if let move = ChessEngine.Move(fromUCI: moveUCI) {
                _ = engine.makeMove(move)
                boardView.needsDisplay = true
                moveIndex += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    makeNextMove()
                }
            }
        }
        makeNextMove()
    }

    @objc private func nextClicked(_ sender: NSButton) {
        loadNewPuzzle()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func puzzleSolved() {
        stopTimer()
        let solveTime = Date().timeIntervalSince(startTime ?? Date())
        statsManager.recordSolve(time: solveTime, wasCorrect: true)
        updateStats()

        nextButton.isHidden = false
        hintButton.isEnabled = false
        solutionButton.isEnabled = false

        showAlert(title: "Puzzle Solved!", message: "Great job! Time: \(formatTime(solveTime))")
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    deinit {
        stopTimer()
    }
}

extension PuzzleWindowController: ChessBoardViewDelegate {
    func chessBoardView(_ view: ChessBoardView, didMakeMove from: ChessEngine.Square, to: ChessEngine.Square) {
        guard let engine = engine else { return }

        // Only allow moves on player's turn
        guard puzzleManager.isPlayerTurn() else { return }

        let move = ChessEngine.Move(from: from, to: to)
        let moveUCI = move.uci

        // Validate move
        if puzzleManager.validateMove(moveUCI) {
            _ = engine.makeMove(move)
            puzzleManager.advanceToNextMove()
            boardView.clearSelection()
            boardView.needsDisplay = true
            updateStatusLabel()

            // Check if puzzle is complete after player's move
            if puzzleManager.isPuzzleComplete() {
                puzzleSolved()
            } else {
                // Automatically make the engine's move
                makeEngineMove()
            }
        } else {
            // Wrong move
            showAlert(title: "Incorrect Move", message: "That's not the correct move. Try again!")
            boardView.clearSelection()
            boardView.needsDisplay = true
        }
    }

    private func makeEngineMove() {
        guard let engine = engine,
              let engineMoveUCI = puzzleManager.getNextEngineMove(),
              let engineMove = ChessEngine.Move(fromUCI: engineMoveUCI) else {
            return
        }

        // Make the engine move
        _ = engine.makeMove(engineMove)
        puzzleManager.advanceToNextMove()
        boardView.clearSelection()
        boardView.needsDisplay = true
        updateStatusLabel()

        // Check if puzzle is complete after engine's move
        if puzzleManager.isPuzzleComplete() {
            puzzleSolved()
        }
    }

    func chessBoardView(_ view: ChessBoardView, shouldHighlightSquare square: ChessEngine.Square) -> Bool {
        guard let selectedSquare = view.selectedSquare,
              puzzleManager.isPlayerTurn() else { return false }

        // For puzzle mode, we'll highlight squares that are part of the solution
        // This is a simplified version - in a full implementation, we'd check legal moves
        let move = ChessEngine.Move(from: selectedSquare, to: square)
        let moveUCI = move.uci

        // Check if this move matches the next move in the solution
        if let hint = puzzleManager.getHint() {
            return moveUCI.lowercased() == hint.lowercased()
        }

        return false
    }
}

