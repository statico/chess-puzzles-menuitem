import SwiftUI
import AppKit

// Protocol for dependency injection
protocol PuzzleManagerProtocol {
    func getNextPuzzle() -> Puzzle?
    func getPlayerColor() -> ChessEngine.Color?
    func isPlayerTurn() -> Bool
    func validateMove(_ moveUCI: String) -> Bool
    func advanceToNextMove()
    func isPuzzleComplete() -> Bool
    func getHint() -> String?
    func getSolution() -> [String]
    func getNextEngineMove() -> String?
}

protocol StatsManagerProtocol {
    func getStats() -> PuzzleStats
    func recordSolve(time: TimeInterval, wasCorrect: Bool)
}

// Make PuzzleManager conform to the protocol
extension PuzzleManager: PuzzleManagerProtocol {}
extension StatsManager: StatsManagerProtocol {}

class PuzzleMenuItemViewModel: ObservableObject {
    @Published var engine: ChessEngine?
    @Published var statusText: String = "White to move"
    @Published var timerText: String = "00:00"
    @Published var streakText: String = "Streak: 0"
    @Published var messageText: String = ""
    @Published var messageColor: Color = .secondary
    @Published var nextButtonTitle: String = "Skip"
    @Published var nextButtonAction: NextButtonAction = .skip
    @Published var hintButtonEnabled: Bool = true
    @Published var solutionButtonEnabled: Bool = true
    @Published var showNextButton: Bool = true

    enum NextButtonAction {
        case skip
        case next
    }

    private let puzzleManager: PuzzleManagerProtocol
    private let statsManager: StatsManagerProtocol
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var timer: Timer?
    private var messageTimer: Timer?
    var isMenuOpen: Bool = false {
        didSet {
            if isMenuOpen {
                startTimer()
            } else {
                pauseTimer()
            }
        }
    }

    init(puzzleManager: PuzzleManagerProtocol = PuzzleManager.shared, statsManager: StatsManagerProtocol = StatsManager.shared) {
        self.puzzleManager = puzzleManager
        self.statsManager = statsManager
        updateStats()
    }

    func loadNewPuzzle() {
        guard let puzzle = puzzleManager.getNextPuzzle() else {
            statusText = "No puzzles available"
            showMessage("No puzzles available. Please download the puzzle database.", color: .red)
            return
        }

        engine = ChessEngine(fen: puzzle.fen)
        updateStatusLabel()
        pausedTime = 0
        startTime = nil
        if isMenuOpen {
            startTimer()
        }
        nextButtonTitle = "Skip"
        nextButtonAction = .skip
        showNextButton = true
        hintButtonEnabled = true
        solutionButtonEnabled = true
        clearMessage()
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

    func menuWillOpen() {
        isMenuOpen = true
        if engine != nil {
            startTimer()
        }
    }

    func menuDidClose() {
        isMenuOpen = false
        pauseTimer()
    }

    private func startTimer() {
        guard isMenuOpen else { return }
        stopTimer()

        // If we have paused time, adjust startTime to account for it
        if pausedTime > 0 {
            startTime = Date().addingTimeInterval(-pausedTime)
        } else {
            startTime = Date()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, self.isMenuOpen else {
                timer.invalidate()
                return
            }
            self.updateTimer()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateTimer()
    }

    private func pauseTimer() {
        guard let startTime = startTime else { return }
        // Calculate total elapsed time including paused time
        let elapsed = Date().timeIntervalSince(startTime)
        pausedTime = elapsed
        stopTimer()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTimer() {
        guard let startTime = startTime, isMenuOpen else {
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
        showMessage("Hint: First move is \(hint)", color: .blue)
    }

    func solutionClicked() {
        let solution = puzzleManager.getSolution()
        let solutionText = solution.joined(separator: " ")
        showMessage("Solution: \(solutionText)", color: .orange)
        showSolution()
    }

    private func showSolution() {
        stopTimer()
        nextButtonTitle = "Next"
        nextButtonAction = .next
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

    func skipClicked() {
        loadNewPuzzle()
    }

    func nextClicked() {
        loadNewPuzzle()
    }

    private func showMessage(_ message: String, color: Color) {
        messageTimer?.invalidate()
        messageText = message
        messageColor = color

        // Auto-clear message after 5 seconds
        messageTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.clearMessage()
        }
    }

    func clearMessage() {
        messageTimer?.invalidate()
        messageTimer = nil
        messageText = ""
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
            puzzleManager.advanceToNextMove()
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
            showMessage("Incorrect move. Try again!", color: .red)
        }
    }

    func shouldHighlightSquare(_ square: ChessEngine.Square, selectedSquare: ChessEngine.Square?) -> Bool {
        guard let selectedSquare = selectedSquare,
              puzzleManager.isPlayerTurn() else { return false }

        // For puzzle mode, we'll highlight squares that are part of the solution
        let move = ChessEngine.Move(from: selectedSquare, to: square)
        let moveUCI = move.uci

        // Check if this move matches the next move in the solution
        if let hint = puzzleManager.getHint() {
            return moveUCI.lowercased() == hint.lowercased()
        }

        return false
    }

    func getPlayerColor() -> ChessEngine.Color {
        return puzzleManager.getPlayerColor() ?? .white
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
        updateStatusLabel()

        // Check if puzzle is complete after engine's move
        if puzzleManager.isPuzzleComplete() {
            puzzleSolved()
        }
    }

    private func puzzleSolved() {
        stopTimer()
        let solveTime = Date().timeIntervalSince(startTime ?? Date())
        statsManager.recordSolve(time: solveTime, wasCorrect: true)
        updateStats()

        nextButtonTitle = "Next"
        nextButtonAction = .next
        showNextButton = true
        hintButtonEnabled = false
        solutionButtonEnabled = false

        showMessage("Puzzle Solved! Time: \(formatTime(solveTime))", color: .green)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    deinit {
        stopTimer()
        messageTimer?.invalidate()
    }
}

struct PuzzleMenuItemContentView: View {
    @StateObject private var viewModel: PuzzleMenuItemViewModel
    @State private var boardColor: BoardColor
    @State private var boardSize: BoardSize

    init(
        viewModel: PuzzleMenuItemViewModel? = nil,
        boardColor: BoardColor? = nil,
        boardSize: BoardSize? = nil
    ) {
        // Use provided viewModel or create default one
        if let viewModel = viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            _viewModel = StateObject(wrappedValue: PuzzleMenuItemViewModel())
        }

        // Use provided values or load from UserDefaults (only in non-preview contexts)
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // In preview mode, use defaults
            _boardColor = State(initialValue: boardColor ?? .green)
            _boardSize = State(initialValue: boardSize ?? .medium)
        } else {
            _boardColor = State(initialValue: boardColor ?? BoardColor.load())
            _boardSize = State(initialValue: boardSize ?? BoardSize.load())
        }
        #else
        _boardColor = State(initialValue: boardColor ?? BoardColor.load())
        _boardSize = State(initialValue: boardSize ?? BoardSize.load())
        #endif
    }

    var body: some View {
        let boardSizeValue = boardSize.size
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        let messageHeight = controlHeight * 1.5

        VStack(spacing: spacing) {
            // Status row
            HStack {
                Text(viewModel.statusText)
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                Text(viewModel.timerText)
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
            }
            .frame(height: controlHeight)

            // Board
            ChessBoardView(
                engine: viewModel.engine,
                playerColor: viewModel.getPlayerColor(),
                showCoordinates: boardSize != .small,
                onMove: { from, to in
                    viewModel.handleMove(from: from, to: to)
                },
                shouldHighlight: { square, selectedSquare in
                    viewModel.shouldHighlightSquare(square, selectedSquare: selectedSquare)
                }
            )
            .frame(width: boardSizeValue, height: boardSizeValue)

            // Streak label
            HStack {
                Text(viewModel.streakText)
                    .font(.system(size: 12))
                Spacer()
            }
            .frame(height: controlHeight)

            // Buttons row
            HStack(spacing: 10) {
                Button("Hint") {
                    viewModel.hintClicked()
                }
                .disabled(!viewModel.hintButtonEnabled)

                Button("Solution") {
                    viewModel.solutionClicked()
                }
                .disabled(!viewModel.solutionButtonEnabled)

                if viewModel.showNextButton {
                    Button(viewModel.nextButtonTitle) {
                        switch viewModel.nextButtonAction {
                        case .skip:
                            viewModel.skipClicked()
                        case .next:
                            viewModel.nextClicked()
                        }
                    }
                }
            }
            .frame(height: controlHeight)

            // Message label
            Text(viewModel.messageText)
                .font(.system(size: 12))
                .foregroundColor(viewModel.messageColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: messageHeight)
        }
        .padding(padding)
        .frame(width: boardSizeValue + (padding * 2), alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            viewModel.loadNewPuzzle()
        }
    }

    func loadNewPuzzle() {
        viewModel.loadNewPuzzle()
    }

    func setBoardColor(_ color: BoardColor) {
        boardColor = color
        // Update the board view's color
        // This will need to be passed to ChessBoardView
    }

    func setBoardSize(_ size: BoardSize) {
        boardSize = size
    }

    func menuWillOpen() {
        viewModel.menuWillOpen()
    }

    func menuDidClose() {
        viewModel.menuDidClose()
    }
}

// Wrapper class to maintain compatibility with existing code
public class PuzzleMenuItemView: NSView {
    private var hostingView: NSHostingView<PuzzleMenuItemContentView>?
    private var puzzleView: PuzzleMenuItemContentView?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Calculate and set the proper frame size first
        updateFrame()

        let puzzleView = PuzzleMenuItemContentView()
        self.puzzleView = puzzleView

        let hostingView = NSHostingView(rootView: puzzleView)
        self.hostingView = hostingView

        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Force the hosting view to update its size
        hostingView.invalidateIntrinsicContentSize()
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        // Ensure hosting view is properly sized
        if let hostingView = hostingView {
            hostingView.frame = bounds
        }
    }

    private func updateFrame() {
        let boardSize = BoardSize.load()
        let boardSizeValue = boardSize.size
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        let messageHeight = controlHeight * 1.5

        // Calculate total height: padding + status + board + spacing + streak + spacing + buttons + spacing + message + padding
        let totalHeight = padding + controlHeight + boardSizeValue + spacing + controlHeight + spacing + controlHeight + spacing + messageHeight + padding
        let totalWidth = boardSizeValue + (padding * 2)

        // Set the frame
        self.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Prevent horizontal stretching
        autoresizingMask = [.height]
    }

    public override var intrinsicContentSize: NSSize {
        let boardSize = BoardSize.load()
        let boardSizeValue = boardSize.size
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        let messageHeight = controlHeight * 1.5

        let totalHeight = padding + controlHeight + boardSizeValue + spacing + controlHeight + spacing + controlHeight + spacing + messageHeight + padding
        let totalWidth = boardSizeValue + (padding * 2)

        return NSSize(width: totalWidth, height: totalHeight)
    }

    public func loadNewPuzzle() {
        puzzleView?.loadNewPuzzle()
    }

    public func setBoardColor(_ color: BoardColor) {
        puzzleView?.setBoardColor(color)
    }

    public func setBoardSize(_ size: BoardSize) {
        puzzleView?.setBoardSize(size)
        // Update frame when board size changes
        updateFrame()
        invalidateIntrinsicContentSize()
    }

    public func menuWillOpen() {
        puzzleView?.menuWillOpen()
    }

    public func menuDidClose() {
        puzzleView?.menuDidClose()
    }
}

#Preview("Puzzle Menu Item - Medium") {
    PreviewWrapper()
        .frame(width: 340)
}

#Preview("Puzzle Menu Item - Small") {
    PreviewWrapper()
        .frame(width: 240)
}

#Preview("Puzzle Menu Item - Large") {
    PreviewWrapper()
        .frame(width: 440)
}

// Mock implementations for previews
private class MockPuzzleManager: PuzzleManagerProtocol {
    func getNextPuzzle() -> Puzzle? {
        return Puzzle(
            id: "preview",
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            moves: ["e2e4", "e7e5"],
            rating: 1500,
            themes: [],
            popularity: nil
        )
    }

    func getPlayerColor() -> ChessEngine.Color? {
        return .white
    }

    func isPlayerTurn() -> Bool {
        return true
    }

    func validateMove(_ moveUCI: String) -> Bool {
        return true
    }

    func advanceToNextMove() {}

    func isPuzzleComplete() -> Bool {
        return false
    }

    func getHint() -> String? {
        return "e2e4"
    }

    func getSolution() -> [String] {
        return ["e2e4", "e7e5"]
    }

    func getNextEngineMove() -> String? {
        return "e7e5"
    }
}

private class MockStatsManager: StatsManagerProtocol {
    func getStats() -> PuzzleStats {
        var stats = PuzzleStats()
        stats.currentStreak = 5
        stats.totalSolved = 100
        stats.userRating = 1500
        return stats
    }

    func recordSolve(time: TimeInterval, wasCorrect: Bool) {}
}

// Preview wrapper that provides safe defaults
private struct PreviewWrapper: View {
    @StateObject private var viewModel: PuzzleMenuItemViewModel
    @State private var boardColor: BoardColor = .green
    @State private var boardSize: BoardSize = .medium

    init() {
        let mockPuzzleManager = MockPuzzleManager()
        let mockStatsManager = MockStatsManager()
        _viewModel = StateObject(wrappedValue: PuzzleMenuItemViewModel(
            puzzleManager: mockPuzzleManager,
            statsManager: mockStatsManager
        ))
    }

    var body: some View {
        let boardSizeValue = boardSize.size
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        let messageHeight = controlHeight * 1.5

        // Create a mock engine for preview
        let mockEngine = ChessEngine(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

        VStack(spacing: spacing) {
            // Status row
            HStack {
                Text("⬜️ White to Move")
                    .font(.system(size: 14, weight: .medium))

                Spacer()

                Text("00:00")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
            }
            .frame(height: controlHeight)

            // Board
            ChessBoardView(
                engine: mockEngine,
                playerColor: .white,
                showCoordinates: boardSize != .small,
                onMove: { _, _ in },
                shouldHighlight: { _, _ in false }
            )
            .frame(width: boardSizeValue, height: boardSizeValue)

            // Streak label
            HStack {
                Text("🟢 Streak: 5")
                    .font(.system(size: 12))
                Spacer()
            }
            .frame(height: controlHeight)

            // Buttons row
            HStack(spacing: 10) {
                Button("Hint") { }
                Button("Solution") { }
                Button("Skip") { }
            }
            .frame(height: controlHeight)

            // Message label
            Text("")
                .font(.system(size: 12))
                .frame(height: messageHeight)
        }
        .padding(padding)
        .frame(width: boardSizeValue + (padding * 2), alignment: .center)
        .fixedSize(horizontal: true, vertical: false)
    }
}
