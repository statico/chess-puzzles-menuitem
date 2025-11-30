import SwiftUI
import AppKit

class PuzzleWindowViewModel: ObservableObject {
    @Published var engine: ChessEngine?
    @Published var statusText: String = "White to move"
    @Published var timerText: String = "00:00"
    @Published var streakText: String = "Streak: 0"
    @Published var showNextButton: Bool = false
    @Published var hintButtonEnabled: Bool = true
    @Published var solutionButtonEnabled: Bool = true
    @Published var selectedDifficulty: Difficulty = .normal
    @Published var opponentLastMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    @Published var animateMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    @Published var canGoBackward: Bool = false
    @Published var canGoForward: Bool = false

    private var puzzleManager = PuzzleManager.shared
    private var statsManager = StatsManager.shared
    private var startTime: Date?
    private var timer: Timer?

    init() {
        selectedDifficulty = puzzleManager.getDifficulty()
        updateStats()
    }

    func loadNewPuzzle() {
        guard let puzzle = puzzleManager.getNextPuzzle() else {
            statusText = "No puzzles available"
            return
        }

        engine = ChessEngine(fen: puzzle.fen)
        animateMove = nil // Clear any previous animation

        // In Lichess format, the first move is the opponent's move - apply it automatically
        if let firstMoveUCI = puzzleManager.getNextEngineMove(),
           let firstMove = ChessEngine.Move(fromUCI: firstMoveUCI),
           let engine = engine {
            print("[DEBUG] PuzzleWindowViewModel.loadNewPuzzle - applying first move \(firstMoveUCI) with animation")
            // Trigger animation before making the move
            animateMove = (from: firstMove.from, to: firstMove.to)
            // Small delay to ensure animation starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = engine.makeMove(firstMove)
                self.puzzleManager.advanceToNextMove()
                // Track the opponent's last move for highlighting
                self.opponentLastMove = (from: firstMove.from, to: firstMove.to)
            }
        } else {
            opponentLastMove = nil
        }

        // Player color will be passed to the board view

        updateStatusLabel()
        startTimer()
        showNextButton = false
        hintButtonEnabled = true
        solutionButtonEnabled = true
        updateNavigationState()
    }

    func updateStatusLabel() {
        guard let engine = engine else { return }
        if puzzleManager.isPlayerTurn() {
            let playerColor = puzzleManager.getPlayerColor()
            let emoji = playerColor == .white ? "⬜️" : "⬛️"
            let colorName = playerColor == .white ? "White" : "Black"
            statusText = "\(emoji) \(colorName) to Move"
        } else {
            let engineColor = engine.getActiveColor() == .white ? "White" : "Black"
            statusText = "Engine thinking (\(engineColor))..."
        }
    }

    func startTimer() {
        stopTimer()
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
        updateTimer()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTimer() {
        guard let startTime = startTime else {
            timerText = "00:00"
            return
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        timerText = String(format: "%02d:%02d", minutes, seconds)
    }

    func updateStats() {
        let stats = statsManager.getStats()
        let streak = stats.currentStreak
        let emoji: String
        switch streak {
        case 0:
            emoji = "⚫️"
        case 1...2:
            emoji = "🟢"
        case 3...4:
            emoji = "🟡"
        case 5...7:
            emoji = "🟠"
        case 8...10:
            emoji = "🔴"
        default:
            emoji = "🔥"
        }
        streakText = "\(emoji) Streak: \(streak)"
    }

    func hintClicked() {
        guard let hint = puzzleManager.getHint() else { return }
        showAlert(title: "Hint", message: "First move: \(hint)")
    }

    func solutionClicked() {
        let solution = puzzleManager.getSolution()
        let solutionText = solution.joined(separator: " ")
        showAlert(title: "Solution", message: solutionText)
        showSolution()
    }

    private func showSolution() {
        stopTimer()
        showNextButton = true
        hintButtonEnabled = false
        solutionButtonEnabled = false

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
                moveIndex += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    makeNextMove()
                }
            }
        }
        makeNextMove()
    }

    func nextClicked() {
        loadNewPuzzle()
    }

    func difficultyChanged(_ difficulty: Difficulty) {
        puzzleManager.setDifficulty(difficulty)
        selectedDifficulty = difficulty
        loadNewPuzzle()
    }

    func handleMove(from: ChessEngine.Square, to: ChessEngine.Square) {
        guard let engine = engine else { return }

        // Only allow moves on player's turn
        guard puzzleManager.isPlayerTurn() else { return }

        let move = ChessEngine.Move(from: from, to: to)
        let moveUCI = move.uci

        // Validate move
        if puzzleManager.validateMove(moveUCI) {
            _ = engine.makeMove(move)
            // Clear opponent's last move highlight since player just moved
            opponentLastMove = nil
            puzzleManager.advanceToNextMove()
            updateStatusLabel()
            updateNavigationState()

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
        }
    }

    @Published var selectedSquare: ChessEngine.Square?

    func shouldHighlightSquare(_ square: ChessEngine.Square, selectedSquare: ChessEngine.Square?) -> Bool {
        guard let selectedSquare = selectedSquare else { return false }
        guard puzzleManager.isPlayerTurn() else { return false }

        // For puzzle mode, we'll highlight squares that are part of the solution
        let move = ChessEngine.Move(from: selectedSquare, to: square)
        let moveUCI = move.uci

        // Check if this move matches the next move in the solution
        if let hint = puzzleManager.getHint() {
            return moveUCI.lowercased() == hint.lowercased()
        }

        return false
    }

    private func makeEngineMove() {
        guard let engine = engine,
              let engineMoveUCI = puzzleManager.getNextEngineMove(),
              let engineMove = ChessEngine.Move(fromUCI: engineMoveUCI) else {
            print("[DEBUG] PuzzleWindowViewModel.makeEngineMove - no engine move available")
            return
        }

        print("[DEBUG] PuzzleWindowViewModel.makeEngineMove - animating engine move \(engineMoveUCI)")
        // Trigger animation before making the move
        animateMove = (from: engineMove.from, to: engineMove.to)

        // Small delay to ensure animation starts, then make the move
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = engine.makeMove(engineMove)
            // Track the opponent's last move for highlighting
            self.opponentLastMove = (from: engineMove.from, to: engineMove.to)
            self.puzzleManager.advanceToNextMove()
            self.updateStatusLabel()
            self.updateNavigationState()

            // Check if puzzle is complete after engine's move
            if self.puzzleManager.isPuzzleComplete() {
                self.puzzleSolved()
            }
        }
    }

    private func puzzleSolved() {
        stopTimer()
        let solveTime = Date().timeIntervalSince(startTime ?? Date())
        statsManager.recordSolve(time: solveTime, wasCorrect: true)
        updateStats()

        showNextButton = true
        hintButtonEnabled = false
        solutionButtonEnabled = false

        showAlert(title: "Puzzle Solved!", message: "Great job! Time: \(formatTime(solveTime))")
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func updateNavigationState() {
        canGoBackward = puzzleManager.canGoBackward()
        canGoForward = puzzleManager.canGoForward()
        print("[DEBUG] PuzzleWindowViewModel.updateNavigationState - canGoBackward: \(canGoBackward), canGoForward: \(canGoForward)")
    }

    func navigateBackward() {
        print("[DEBUG] PuzzleWindowViewModel.navigateBackward - called")
        guard puzzleManager.goBackward() != nil,
              puzzleManager.getCurrentPuzzle() != nil else {
            print("[DEBUG] PuzzleWindowViewModel.navigateBackward - no move to go back to")
            return
        }

        // Rebuild engine state from puzzle FEN and replay moves up to current position
        rebuildEngineState()
        updateNavigationState()
        updateStatusLabel()
        updateOpponentLastMove()
        print("[DEBUG] PuzzleWindowViewModel.navigateBackward - completed, currentMoveIndex: \(puzzleManager.getCurrentMoveIndex())")
    }

    func navigateForward() {
        print("[DEBUG] PuzzleWindowViewModel.navigateForward - called")
        guard let move = puzzleManager.goForward(),
              let engine = engine,
              let moveObj = ChessEngine.Move(fromUCI: move.moveUCI) else {
            print("[DEBUG] PuzzleWindowViewModel.navigateForward - no move to go forward to")
            return
        }

        // Replay the move in the engine
        print("[DEBUG] PuzzleWindowViewModel.navigateForward - replaying move \(move.moveUCI), isPlayerMove: \(move.isPlayerMove)")
        _ = engine.makeMove(moveObj)

        // Update opponent last move if it was a computer move
        if !move.isPlayerMove {
            opponentLastMove = (from: moveObj.from, to: moveObj.to)
            // Trigger animation for computer moves
            animateMove = (from: moveObj.from, to: moveObj.to)
        } else {
            opponentLastMove = nil
        }

        updateNavigationState()
        updateStatusLabel()
        print("[DEBUG] PuzzleWindowViewModel.navigateForward - completed, currentMoveIndex: \(puzzleManager.getCurrentMoveIndex())")
    }

    private func rebuildEngineState() {
        guard let puzzle = puzzleManager.getCurrentPuzzle() else {
            print("[DEBUG] PuzzleWindowViewModel.rebuildEngineState - no current puzzle")
            return
        }

        print("[DEBUG] PuzzleWindowViewModel.rebuildEngineState - rebuilding from FEN: \(puzzle.fen)")
        engine = ChessEngine(fen: puzzle.fen)

        // Replay moves up to currentHistoryIndex
        let movesToReplay = puzzleManager.getMovesUpToHistoryIndex()
        print("[DEBUG] PuzzleWindowViewModel.rebuildEngineState - replaying \(movesToReplay.count) moves")

        guard let engine = engine else { return }

        for moveUCI in movesToReplay {
            if let move = ChessEngine.Move(fromUCI: moveUCI) {
                _ = engine.makeMove(move)
            }
        }

        updateOpponentLastMove()
    }

    private func updateOpponentLastMove() {
        opponentLastMove = puzzleManager.getOpponentLastMove()
    }

    deinit {
        stopTimer()
    }
}

struct PuzzleWindowView: View {
    @StateObject private var viewModel = PuzzleWindowViewModel()
    @State private var boardColor: BoardColor = BoardColor.load()
    @State private var boardSize: BoardSize = BoardSize.load()

    var body: some View {
        VStack(spacing: 15) {
            // Header row
            HStack {
                Text(viewModel.statusText)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Text(viewModel.timerText)
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 60)

            // Stats and difficulty row
            HStack {
                Text(viewModel.streakText)
                    .font(.system(size: 14))

                Spacer()

                Picker("Difficulty", selection: $viewModel.selectedDifficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.rawValue).tag(difficulty)
                    }
                }
                .frame(width: 200)
                .onChange(of: viewModel.selectedDifficulty) { newValue in
                    viewModel.difficultyChanged(newValue)
                }
            }
            .padding(.horizontal, 60)

            // Chess board
            ChessBoardView(
                engine: viewModel.engine,
                playerColor: PuzzleManager.shared.getPlayerColor(),
                showCoordinates: true,
                onMove: { from, to in
                    viewModel.handleMove(from: from, to: to)
                },
                shouldHighlight: { square, selectedSquare in
                    viewModel.shouldHighlightSquare(square, selectedSquare: selectedSquare)
                },
                opponentLastMove: viewModel.opponentLastMove,
                animateMove: viewModel.animateMove
            )
            .frame(width: 480, height: 480)

            // Buttons row
            HStack(spacing: 10) {
                Button("<") {
                    viewModel.navigateBackward()
                }
                .disabled(!viewModel.canGoBackward)

                Button(">") {
                    viewModel.navigateForward()
                }
                .disabled(!viewModel.canGoForward)

                Button("Hint") {
                    viewModel.hintClicked()
                }
                .disabled(!viewModel.hintButtonEnabled)

                Button("Solution") {
                    viewModel.solutionClicked()
                }
                .disabled(!viewModel.solutionButtonEnabled)

                if viewModel.showNextButton {
                    Button("Next") {
                        viewModel.nextClicked()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                }
            }
            .padding(.horizontal, 60)
        }
        .frame(width: 600, height: 700)
        .padding()
        .onAppear {
            viewModel.loadNewPuzzle()
        }
    }
}

// Wrapper class to maintain compatibility with existing code
class PuzzleWindowController: NSWindowController {
    private var hostingController: NSHostingController<PuzzleWindowView>?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let puzzleView = PuzzleWindowView()
        let hostingController = NSHostingController(rootView: puzzleView)
        self.hostingController = hostingController

        window.contentView = hostingController.view
        window.title = "Chess Puzzle"
        window.center()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func loadNewPuzzle() {
        // The view model will handle this automatically via SwiftUI
    }
}

#Preview("Puzzle Window") {
    PuzzleWindowView()
        .frame(width: 600, height: 700)
}

