import AppKit

class PuzzleMenuItemView: NSView {
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    private func setupUI() {
        // Total view size: 400px board + padding + controls
        let boardSize: CGFloat = 400
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 30
        let spacing: CGFloat = 10

        // Layout from top to bottom:
        // - Top padding
        // - Status row
        // - Spacing
        // - Streak row
        // - Spacing
        // - Buttons row
        // - Spacing
        // - Board (400px)
        // - Bottom padding

        let totalHeight = padding + controlHeight + spacing + controlHeight + spacing + controlHeight + spacing + boardSize + padding
        let totalWidth = boardSize + (padding * 2)

        // Set frame to accommodate all content
        self.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        var currentY = totalHeight - padding - controlHeight

        // Status label (top left)
        let statusLabel = NSTextField(labelWithString: "White to move")
        statusLabel.frame = NSRect(x: padding, y: currentY, width: 200, height: controlHeight)
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        addSubview(statusLabel)
        self.statusLabel = statusLabel

        // Timer label (top right)
        let timerLabel = NSTextField(labelWithString: "00:00")
        timerLabel.frame = NSRect(x: totalWidth - padding - 200, y: currentY, width: 200, height: controlHeight)
        timerLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        timerLabel.alignment = .right
        addSubview(timerLabel)
        self.timerLabel = timerLabel

        currentY -= (controlHeight + spacing)

        // Streak label (second row left)
        let streakLabel = NSTextField(labelWithString: "Streak: 0")
        streakLabel.frame = NSRect(x: padding, y: currentY, width: 200, height: controlHeight)
        streakLabel.font = NSFont.systemFont(ofSize: 12)
        addSubview(streakLabel)
        self.streakLabel = streakLabel

        currentY -= (controlHeight + spacing)

        // Buttons row
        let buttonWidth: CGFloat = 100
        let buttonSpacing: CGFloat = 10

        // Hint button
        let hintButton = NSButton(title: "Hint", target: self, action: #selector(hintClicked(_:)))
        hintButton.frame = NSRect(x: padding, y: currentY, width: buttonWidth, height: controlHeight)
        hintButton.bezelStyle = .rounded
        addSubview(hintButton)
        self.hintButton = hintButton

        // Solution button
        let solutionButton = NSButton(title: "Solution", target: self, action: #selector(solutionClicked(_:)))
        solutionButton.frame = NSRect(x: padding + buttonWidth + buttonSpacing, y: currentY, width: buttonWidth, height: controlHeight)
        solutionButton.bezelStyle = .rounded
        addSubview(solutionButton)
        self.solutionButton = solutionButton

        // Next button (initially hidden)
        let nextButton = NSButton(title: "Next", target: self, action: #selector(nextClicked(_:)))
        nextButton.frame = NSRect(x: padding + (buttonWidth + buttonSpacing) * 2, y: currentY, width: buttonWidth, height: controlHeight)
        nextButton.bezelStyle = .rounded
        nextButton.isHidden = true
        addSubview(nextButton)
        self.nextButton = nextButton

        currentY -= (controlHeight + spacing)

        // Board view (positioned below buttons)
        let boardY = padding
        let boardView = ChessBoardView(frame: NSRect(x: padding, y: boardY, width: boardSize, height: boardSize))
        boardView.delegate = self
        addSubview(boardView)
        self.boardView = boardView

        updateStats()

        // Load initial puzzle
        loadNewPuzzle()
    }

    func loadNewPuzzle() {
        guard let puzzle = puzzleManager.getNextPuzzle() else {
            statusLabel.stringValue = "No puzzles available"
            return
        }

        engine = ChessEngine(fen: puzzle.fen)
        boardView.setEngine(engine!)

        updateStatusLabel()
        startTimer()
        nextButton.isHidden = true
        hintButton.isEnabled = true
        solutionButton.isEnabled = true

        boardView.clearSelection()
    }

    private func updateStatusLabel() {
        guard let engine = engine else { return }
        let color = engine.getActiveColor() == .white ? "White" : "Black"
        statusLabel.stringValue = "\(color) to move"
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

extension PuzzleMenuItemView: ChessBoardViewDelegate {
    func chessBoardView(_ view: ChessBoardView, didMakeMove from: ChessEngine.Square, to: ChessEngine.Square) {
        guard let engine = engine else { return }

        let move = ChessEngine.Move(from: from, to: to)
        let moveUCI = move.uci

        // Validate move
        if puzzleManager.validateMove(moveUCI) {
            _ = engine.makeMove(move)
            puzzleManager.advanceToNextMove()
            boardView.clearSelection()
            boardView.needsDisplay = true
            updateStatusLabel()

            if puzzleManager.isPuzzleComplete() {
                puzzleSolved()
            }
        } else {
            // Wrong move
            showAlert(title: "Incorrect Move", message: "That's not the correct move. Try again!")
            boardView.clearSelection()
            boardView.needsDisplay = true
        }
    }

    func chessBoardView(_ view: ChessBoardView, shouldHighlightSquare square: ChessEngine.Square) -> Bool {
        guard let selectedSquare = view.selectedSquare else { return false }

        // For puzzle mode, we'll highlight squares that are part of the solution
        let move = ChessEngine.Move(from: selectedSquare, to: square)
        let moveUCI = move.uci

        // Check if this move matches the next move in the solution
        if let hint = puzzleManager.getHint() {
            return moveUCI.lowercased() == hint.lowercased()
        }

        return false
    }
}

