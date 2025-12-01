import SwiftUI
import AppKit

// Protocol for dependency injection
@MainActor
protocol PuzzleManagerProtocol {
    func getNextPuzzle() -> Puzzle?
    func getCurrentPuzzle() -> Puzzle?
    func getPlayerColor() -> ChessEngine.Color?
    func isPlayerTurn() -> Bool
    func validateMove(_ moveUCI: String) -> Bool
    func advanceToNextMove()
    func isPuzzleComplete() -> Bool
    func getHint() -> String?
    func getSolution() -> [String]
    func getNextEngineMove() -> String?
    func getOpponentLastMove() -> (from: ChessEngine.Square, to: ChessEngine.Square)?
    func getCurrentMoveIndex() -> Int
    func canGoBackward() -> Bool
    func canGoForward() -> Bool
    func goBackward() -> (moveUCI: String, isPlayerMove: Bool)?
    func goForward() -> (moveUCI: String, isPlayerMove: Bool)?
}

// Make PuzzleManager conform to the protocol
@MainActor
extension PuzzleManager: PuzzleManagerProtocol {}

@MainActor
class PuzzleMenuItemViewModel: ObservableObject {
    @Published var engine: ChessEngine?
    @Published var statusText: String = "White to move"
    @Published var messageText: String = ""
    @Published var messageColor: Color = .secondary
    @Published var nextButtonTitle: String = "Skip"
    @Published var nextButtonAction: NextButtonAction = .skip
    @Published var hintButtonEnabled: Bool = true
    @Published var solutionButtonEnabled: Bool = true
    @Published var showNextButton: Bool = true
    @Published var opponentLastMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    @Published var animateMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    @Published var canGoBackward: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isPuzzleSolved: Bool = false

    private var solutionMoveIndex: Int = 0

    enum NextButtonAction {
        case skip
        case next
    }

    private let puzzleManager: PuzzleManagerProtocol
    private var messageTimer: Timer?
    private var hasLoadedPuzzle: Bool = false

    init(puzzleManager: PuzzleManagerProtocol = PuzzleManager.shared) {
        self.puzzleManager = puzzleManager
    }

    func loadNewPuzzle() {
        print("[DEBUG] PuzzleMenuItemViewModel.loadNewPuzzle - called")
        guard let puzzle = puzzleManager.getNextPuzzle() else {
            print("[DEBUG] PuzzleMenuItemViewModel.loadNewPuzzle - no puzzle available")
            statusText = "No puzzles available"
            showMessage("No puzzles available. Please download the puzzle database.", color: .red)
            return
        }

        print("[DEBUG] PuzzleMenuItemViewModel.loadNewPuzzle - loading puzzle with FEN: \(puzzle.fen)")
        engine = ChessEngine(fen: puzzle.fen)
        animateMove = nil // Clear any previous animation
        print("[DEBUG] PuzzleMenuItemViewModel.loadNewPuzzle - engine created, animateMove cleared")

        // In Lichess format, the first move is the opponent's move - apply it automatically
        if let firstMoveUCI = puzzleManager.getNextEngineMove(),
           let firstMove = ChessEngine.Move(fromUCI: firstMoveUCI),
           let engine = engine {
            print("[DEBUG] PuzzleMenuItemViewModel.loadNewPuzzle - applying first move \(firstMoveUCI) with animation")
            // Update yellow squares BEFORE animation starts
            opponentLastMove = (from: firstMove.from, to: firstMove.to)
            // Trigger animation before making the move
            animateMove = (from: firstMove.from, to: firstMove.to)
            // Make engine move happen at 98% of animation, same time as animated piece is cleared
            let animationDuration: TimeInterval = 0.25
            let moveDelay = animationDuration * 0.98
            DispatchQueue.main.asyncAfter(deadline: .now() + moveDelay) {
                print("[DEBUG] PuzzleMenuItemViewModel.loadNewPuzzle - making engine move at \(moveDelay)s (98% of animation)")
                _ = engine.makeMove(firstMove)
                self.puzzleManager.advanceToNextMove()
                // Clear animation trigger immediately after engine move
                self.animateMove = nil
            }
        } else {
            opponentLastMove = nil
        }

        updateStatusLabel()
        nextButtonTitle = "Skip"
        nextButtonAction = .skip
        showNextButton = true
        hintButtonEnabled = true
        solutionButtonEnabled = true
        isPuzzleSolved = false
        hasLoadedPuzzle = true
        updateNavigationState()
        clearMessage()

        // Notify that new puzzle is loaded so menu item can be disabled
        NotificationCenter.default.post(name: NSNotification.Name("PuzzleLoaded"), object: nil)
    }

    func updateStatusLabel() {
        guard engine != nil else {
            print("[DEBUG] PuzzleMenuItemViewModel.updateStatusLabel - no engine")
            return
        }
        let playerColor = puzzleManager.getPlayerColor()
        let emoji = playerColor == .white ? "⬜️" : "⬛️"
        let colorName = playerColor == .white ? "White" : "Black"
        statusText = "\(emoji) \(colorName) to Move"
        print("[DEBUG] PuzzleMenuItemViewModel.updateStatusLabel - updated to: \(statusText), playerColor: \(String(describing: playerColor)), isPlayerTurn: \(puzzleManager.isPlayerTurn())")
    }

    func menuWillOpen() {
        print("[DEBUG] PuzzleMenuItemViewModel.menuWillOpen - called, engine: \(engine != nil ? "exists" : "nil")")
    }

    func menuDidClose() {
        print("[DEBUG] PuzzleMenuItemViewModel.menuDidClose - called")
    }

    func hintClicked() {
        guard let hint = puzzleManager.getHint() else { return }
        showMessage("Hint: \(hint)", color: .blue)
    }

    func solutionClicked() {
        let solution = puzzleManager.getSolution()
        let solutionText = solution.joined(separator: " ")
        showMessage("Solution: \(solutionText)", color: .orange)
        showSolution()
    }

    private func showSolution() {
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
        solutionMoveIndex = 0

        func makeNextMove() {
            guard solutionMoveIndex < solution.count else { return }
            let moveUCI = solution[solutionMoveIndex]
            if let move = ChessEngine.Move(fromUCI: moveUCI) {
                _ = engine.makeMove(move)
                solutionMoveIndex += 1
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
            Task { @MainActor in
                self?.clearMessage()
            }
        }
    }

    func clearMessage() {
        messageTimer?.invalidate()
        messageTimer = nil
        messageText = ""
    }

    private func updateNavigationState() {
        canGoBackward = puzzleManager.canGoBackward()
        canGoForward = puzzleManager.canGoForward()
        print("[DEBUG] PuzzleMenuItemViewModel.updateNavigationState - canGoBackward: \(canGoBackward), canGoForward: \(canGoForward)")
    }

    func handleMove(from: ChessEngine.Square, to: ChessEngine.Square) {
        print("[DEBUG] PuzzleMenuItemViewModel.handleMove - called, from: \(from.uci), to: \(to.uci)")
        guard let engine = engine else {
            print("[DEBUG] PuzzleMenuItemViewModel.handleMove - no engine")
            return
        }

        // Only allow moves on player's turn
        guard puzzleManager.isPlayerTurn() else {
            print("[DEBUG] PuzzleMenuItemViewModel.handleMove - not player's turn, isPlayerTurn: \(puzzleManager.isPlayerTurn())")
            return
        }

        let move = ChessEngine.Move(from: from, to: to)
        let moveUCI = move.uci
        print("[DEBUG] PuzzleMenuItemViewModel.handleMove - moveUCI: \(moveUCI)")

        // Validate move
        if puzzleManager.validateMove(moveUCI) {
            print("[DEBUG] PuzzleMenuItemViewModel.handleMove - move validated, making move")
            _ = engine.makeMove(move)
            // Clear opponent's last move highlight since player just moved
            opponentLastMove = nil
            puzzleManager.advanceToNextMove()
            updateStatusLabel()
            updateNavigationState()

            // Check if puzzle is complete after player's move
            if puzzleManager.isPuzzleComplete() {
                print("[DEBUG] PuzzleMenuItemViewModel.handleMove - puzzle complete after player move")
                puzzleSolved()
            } else {
                // Automatically make the engine's move
                print("[DEBUG] PuzzleMenuItemViewModel.handleMove - puzzle not complete, making engine move")
                makeEngineMove()
            }
        } else {
            // Wrong move
            print("[DEBUG] PuzzleMenuItemViewModel.handleMove - move invalid")
            showMessage("Incorrect move. Try again!", color: .red)
        }
    }

    func shouldHighlightSquare(_ square: ChessEngine.Square, selectedSquare: ChessEngine.Square?) -> Bool {
        guard let selectedSquare = selectedSquare,
              let engine = engine else {
            return false
        }

        guard puzzleManager.isPlayerTurn() else {
            return false
        }

        // Don't highlight the source square
        if square == selectedSquare {
            return false
        }

        // Get all legal moves for the selected piece
        let legalMoves = engine.getLegalMoves(from: selectedSquare)

        // Check if this square is a destination for any legal move
        return legalMoves.contains { $0.to == square }
    }

    func getPlayerColor() -> ChessEngine.Color {
        return puzzleManager.getPlayerColor() ?? .white
    }

    private func makeEngineMove() {
        guard let engine = engine,
              let engineMoveUCI = puzzleManager.getNextEngineMove(),
              let engineMove = ChessEngine.Move(fromUCI: engineMoveUCI) else {
            print("[DEBUG] PuzzleMenuItemViewModel.makeEngineMove - no engine move available")
            return
        }

        print("[DEBUG] PuzzleMenuItemViewModel.makeEngineMove - animating engine move \(engineMoveUCI)")
        // Update yellow squares BEFORE animation starts
        opponentLastMove = (from: engineMove.from, to: engineMove.to)
        // Trigger animation before making the move
        animateMove = (from: engineMove.from, to: engineMove.to)

        // Make engine move happen at 98% of animation, same time as animated piece is cleared
        let animationDuration: TimeInterval = 0.25
        let moveDelay = animationDuration * 0.98
        DispatchQueue.main.asyncAfter(deadline: .now() + moveDelay) {
            print("[DEBUG] PuzzleMenuItemViewModel.makeEngineMove - making engine move at \(moveDelay)s (98% of animation)")
            _ = engine.makeMove(engineMove)
            self.puzzleManager.advanceToNextMove()
            self.updateStatusLabel()
            self.updateNavigationState()
            // Clear animation trigger immediately after engine move
            self.animateMove = nil

            // Check if puzzle is complete after engine's move
            if self.puzzleManager.isPuzzleComplete() {
                self.puzzleSolved()
            }
        }
    }

    private func puzzleSolved() {
        print("[DEBUG] PuzzleMenuItemViewModel.puzzleSolved - called")
        nextButtonTitle = "Next"
        nextButtonAction = .next
        showNextButton = true
        hintButtonEnabled = false
        solutionButtonEnabled = false
        isPuzzleSolved = true

        // Notify that puzzle is solved so menu item can be enabled
        NotificationCenter.default.post(name: NSNotification.Name("PuzzleSolved"), object: nil)

        // Build success message with ELO and popularity
        var message = "Puzzle Solved!"
        if let puzzle = puzzleManager.getCurrentPuzzle() {
            var details: [String] = []
            details.append("ELO \(puzzle.rating)")
            if let popularity = puzzle.popularity {
                details.append("pop. \(popularity)%")
            }
            if !details.isEmpty {
                message += " (\(details.joined(separator: ", ")))"
            }
        }
        print("[DEBUG] PuzzleMenuItemViewModel.puzzleSolved - message: \(message)")
        showMessage(message, color: .green)
    }

    func navigateBackward() {
        print("[DEBUG] PuzzleMenuItemViewModel.navigateBackward - called")
        guard puzzleManager.goBackward() != nil,
              puzzleManager.getCurrentPuzzle() != nil else {
            print("[DEBUG] PuzzleMenuItemViewModel.navigateBackward - no move to go back to")
            return
        }

        // Rebuild engine state from puzzle FEN and replay moves up to current position
        rebuildEngineState()
        updateNavigationState()
        updateStatusLabel()
        updateOpponentLastMove()
        print("[DEBUG] PuzzleMenuItemViewModel.navigateBackward - completed, currentMoveIndex: \(puzzleManager.getCurrentMoveIndex())")
    }

    func navigateForward() {
        print("[DEBUG] PuzzleMenuItemViewModel.navigateForward - called")
        guard let move = puzzleManager.goForward(),
              let engine = engine,
              let moveObj = ChessEngine.Move(fromUCI: move.moveUCI) else {
            print("[DEBUG] PuzzleMenuItemViewModel.navigateForward - no move to go forward to")
            return
        }

        // Replay the move in the engine
        print("[DEBUG] PuzzleMenuItemViewModel.navigateForward - replaying move \(move.moveUCI), isPlayerMove: \(move.isPlayerMove)")
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
        print("[DEBUG] PuzzleMenuItemViewModel.navigateForward - completed, currentMoveIndex: \(puzzleManager.getCurrentMoveIndex())")
    }

    private func rebuildEngineState() {
        guard let puzzle = puzzleManager.getCurrentPuzzle(),
              let puzzleMgr = puzzleManager as? PuzzleManager else {
            print("[DEBUG] PuzzleMenuItemViewModel.rebuildEngineState - no current puzzle or cannot cast")
            return
        }

        print("[DEBUG] PuzzleMenuItemViewModel.rebuildEngineState - rebuilding from FEN: \(puzzle.fen)")
        engine = ChessEngine(fen: puzzle.fen)

        // Replay moves up to currentHistoryIndex
        let movesToReplay = puzzleMgr.getMovesUpToHistoryIndex()
        print("[DEBUG] PuzzleMenuItemViewModel.rebuildEngineState - replaying \(movesToReplay.count) moves")

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
        MainActor.assumeIsolated {
            messageTimer?.invalidate()
        }
    }
}

// Observable object to manage board settings that can be updated from outside
class BoardSettings: ObservableObject {
    @Published var boardColor: BoardColor
    @Published var boardSize: BoardSize

    init(boardColor: BoardColor? = nil, boardSize: BoardSize? = nil) {
        self.boardColor = boardColor ?? BoardColor.load()
        self.boardSize = boardSize ?? BoardSize.load()
    }

    func syncFromUserDefaults() -> Bool {
        let currentColor = BoardColor.load()
        let currentSize = BoardSize.load()
        var changed = false

        if boardColor != currentColor {
            boardColor = currentColor
            changed = true
        }
        if boardSize != currentSize {
            print("[DEBUG] BoardSettings.syncFromUserDefaults - boardSize changed from \(boardSize.rawValue) to \(currentSize.rawValue)")
            boardSize = currentSize
            changed = true
        }
        return changed
    }
}

struct PuzzleMenuItemContentView: View {
    @StateObject private var viewModel: PuzzleMenuItemViewModel
    @ObservedObject var boardSettings: BoardSettings

    init(
        viewModel: PuzzleMenuItemViewModel? = nil,
        boardSettings: BoardSettings? = nil
    ) {
        // Use provided viewModel or create default one
        if let viewModel = viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            _viewModel = StateObject(wrappedValue: PuzzleMenuItemViewModel())
        }

        // Use provided boardSettings or create new one
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // In preview mode, use defaults
            self.boardSettings = boardSettings ?? BoardSettings(boardColor: .green, boardSize: .medium)
        } else {
            let loadedColor = BoardColor.load()
            let loadedSize = BoardSize.load()
            print("[DEBUG] PuzzleMenuItemContentView.init - loaded boardSize: \(loadedSize.rawValue) (\(loadedSize.size)px)")
            self.boardSettings = boardSettings ?? BoardSettings(boardColor: loadedColor, boardSize: loadedSize)
        }
        #else
        let loadedColor = BoardColor.load()
        let loadedSize = BoardSize.load()
        print("[DEBUG] PuzzleMenuItemContentView.init - loaded boardSize: \(loadedSize.rawValue) (\(loadedSize.size)px)")
        self.boardSettings = boardSettings ?? BoardSettings(boardColor: loadedColor, boardSize: loadedSize)
        #endif
    }

    var body: some View {
        let boardSizeValue = boardSettings.boardSize.size
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
            }
            .frame(height: controlHeight)

            // Board
            ChessBoardView(
                engine: viewModel.engine,
                playerColor: viewModel.getPlayerColor(),
                showCoordinates: boardSettings.boardSize != .small,
                onMove: { from, to in
                    viewModel.handleMove(from: from, to: to)
                },
                shouldHighlight: { square, selectedSquare in
                    viewModel.shouldHighlightSquare(square, selectedSquare: selectedSquare)
                },
                opponentLastMove: viewModel.opponentLastMove,
                animateMove: viewModel.animateMove
            )
            .frame(width: boardSizeValue, height: boardSizeValue)
            .id("\(boardSettings.boardSize.rawValue)-\(boardSizeValue)")

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
                    Button(viewModel.nextButtonTitle) {
                        switch viewModel.nextButtonAction {
                        case .skip:
                            viewModel.skipClicked()
                        case .next:
                            viewModel.nextClicked()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isPuzzleSolved ? Color.accentColor : nil)
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
        .id("puzzle-view-\(boardSettings.boardSize.rawValue)-\(boardSizeValue)") // Force view refresh when board size changes
        .onAppear {
            print("[DEBUG] PuzzleMenuItemContentView.body.onAppear - boardSize: \(boardSettings.boardSize.rawValue) (\(boardSettings.boardSize.size)px)")
            // Only load a new puzzle if one hasn't been loaded yet (check if engine exists)
            if viewModel.engine == nil {
                print("[DEBUG] PuzzleMenuItemContentView.body.onAppear - no puzzle loaded yet, loading new puzzle")
                viewModel.loadNewPuzzle()
            } else {
                print("[DEBUG] PuzzleMenuItemContentView.body.onAppear - puzzle already loaded, keeping current puzzle")
            }
        }
        .onChange(of: boardSettings.boardSize) { newSize in
            print("[DEBUG] PuzzleMenuItemContentView.body.onChange - boardSize changed to: \(newSize.rawValue) (\(newSize.size)px)")
        }
    }

    func loadNewPuzzle() {
        viewModel.loadNewPuzzle()
    }

    func setBoardColor(_ color: BoardColor) {
        boardSettings.boardColor = color
        color.save()
    }

    func setBoardSize(_ size: BoardSize) {
        print("[DEBUG] PuzzleMenuItemContentView.setBoardSize - called with: \(size.rawValue) (\(size.size)px), current: \(boardSettings.boardSize.rawValue) (\(boardSettings.boardSize.size)px)")
        boardSettings.boardSize = size
        size.save()
        print("[DEBUG] PuzzleMenuItemContentView.setBoardSize - after update: \(boardSettings.boardSize.rawValue) (\(boardSettings.boardSize.size)px)")
    }

    @discardableResult
    func syncBoardSizeFromUserDefaults() -> Bool {
        return boardSettings.syncFromUserDefaults()
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
    private var boardSettings: BoardSettings?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        print("[DEBUG] PuzzleMenuItemView.setupUI - starting")
        // Calculate and set the proper frame size first
        updateFrame()

        // Create shared BoardSettings object
        let boardSettings = BoardSettings()
        self.boardSettings = boardSettings
        print("[DEBUG] PuzzleMenuItemView.setupUI - created BoardSettings with size: \(boardSettings.boardSize.rawValue) (\(boardSettings.boardSize.size)px)")

        let puzzleView = PuzzleMenuItemContentView(boardSettings: boardSettings)
        self.puzzleView = puzzleView
        print("[DEBUG] PuzzleMenuItemView.setupUI - created PuzzleMenuItemContentView")

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
            // Force the hosting view to recalculate its preferred size
            hostingView.invalidateIntrinsicContentSize()
        }
    }

    private func updateFrame() {
        let boardSize = BoardSize.load()
        let boardSizeValue = boardSize.size
        print("[DEBUG] PuzzleMenuItemView.updateFrame - boardSize: \(boardSize.rawValue) (\(boardSizeValue)px)")
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        let messageHeight = controlHeight * 1.5

        // Calculate total height: padding + status + board + spacing + buttons + spacing + message + padding
        let totalHeight = padding + controlHeight + boardSizeValue + spacing + controlHeight + spacing + messageHeight + padding
        let totalWidth = boardSizeValue + (padding * 2)

        print("[DEBUG] PuzzleMenuItemView.updateFrame - calculated size: \(totalWidth)x\(totalHeight), current frame: \(self.frame)")
        // Set the frame
        self.frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        print("[DEBUG] PuzzleMenuItemView.updateFrame - set frame to: \(self.frame)")

        // Allow both width and height to be set by the menu system
        autoresizingMask = []
    }

    public override var intrinsicContentSize: NSSize {
        let boardSize = BoardSize.load()
        let boardSizeValue = boardSize.size
        let padding: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        let messageHeight = controlHeight * 1.5

        let totalHeight = padding + controlHeight + boardSizeValue + spacing + controlHeight + spacing + messageHeight + padding
        let totalWidth = boardSizeValue + (padding * 2)

        let size = NSSize(width: totalWidth, height: totalHeight)
        print("[DEBUG] PuzzleMenuItemView.intrinsicContentSize - boardSize: \(boardSize.rawValue) (\(boardSizeValue)px), returning: \(size)")
        return size
    }

    public func loadNewPuzzle() {
        puzzleView?.loadNewPuzzle()
    }

    public func setBoardColor(_ color: BoardColor) {
        puzzleView?.setBoardColor(color)
    }

    public func setBoardSize(_ size: BoardSize) {
        print("[DEBUG] PuzzleMenuItemView.setBoardSize - called with: \(size.rawValue) (\(size.size)px)")

        // Update the BoardSettings object directly
        if let boardSettings = boardSettings {
            print("[DEBUG] PuzzleMenuItemView.setBoardSize - current boardSettings.boardSize: \(boardSettings.boardSize.rawValue) (\(boardSettings.boardSize.size)px)")
            boardSettings.boardSize = size
            size.save()
            print("[DEBUG] PuzzleMenuItemView.setBoardSize - after updating boardSettings.boardSize: \(boardSettings.boardSize.rawValue) (\(boardSettings.boardSize.size)px)")
        } else {
            print("[DEBUG] PuzzleMenuItemView.setBoardSize - WARNING: boardSettings is nil!")
        }

        // Update frame when board size changes
        updateFrame()
        invalidateIntrinsicContentSize()
        print("[DEBUG] PuzzleMenuItemView.setBoardSize - after updateFrame, frame: \(self.frame), intrinsicContentSize: \(intrinsicContentSize)")

        // Force hosting view to update and recalculate its size
        hostingView?.invalidateIntrinsicContentSize()
        hostingView?.needsLayout = true

        // Update hosting view frame to match new bounds
        if let hostingView = hostingView {
            hostingView.frame = bounds
            print("[DEBUG] PuzzleMenuItemView.setBoardSize - hostingView.frame set to: \(hostingView.frame)")
        }

        needsLayout = true

        // Notify the menu system that the view size has changed
        // This is critical for NSMenuItem views to resize properly
        if let menuItem = self.enclosingMenuItem {
            print("[DEBUG] PuzzleMenuItemView.setBoardSize - reattaching view to menu item")
            // Temporarily remove and re-add the view to force menu to recalculate
            menuItem.view = nil
            menuItem.view = self
        }

        // Force layout update
        superview?.needsLayout = true
        window?.invalidateCursorRects(for: self)
        print("[DEBUG] PuzzleMenuItemView.setBoardSize - completed")
    }

    public func menuWillOpen() {
        print("[DEBUG] PuzzleMenuItemView.menuWillOpen - called")
        // Reload board size from UserDefaults before opening menu
        // This ensures the view reflects the current setting even if it was changed elsewhere
        let boardSizeChanged = boardSettings?.syncFromUserDefaults() ?? false
        print("[DEBUG] PuzzleMenuItemView.menuWillOpen - boardSizeChanged: \(boardSizeChanged)")

        if boardSizeChanged {
            print("[DEBUG] PuzzleMenuItemView.menuWillOpen - board size changed, updating frame and reattaching view")
            // Update the NSView frame to match the current board size
            updateFrame()
            invalidateIntrinsicContentSize()
            hostingView?.invalidateIntrinsicContentSize()
            needsLayout = true

            // Reattach the view to force the menu to recalculate the item size
            if let menuItem = self.enclosingMenuItem {
                print("[DEBUG] PuzzleMenuItemView.menuWillOpen - reattaching view to menu item")
                menuItem.view = nil
                menuItem.view = self
            }
        } else {
            print("[DEBUG] PuzzleMenuItemView.menuWillOpen - board size unchanged, current frame: \(self.frame), intrinsicContentSize: \(intrinsicContentSize)")
        }

        puzzleView?.menuWillOpen()
        print("[DEBUG] PuzzleMenuItemView.menuWillOpen - completed")
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

    func getOpponentLastMove() -> (from: ChessEngine.Square, to: ChessEngine.Square)? {
        if let move = ChessEngine.Move(fromUCI: "e7e5") {
            return (from: move.from, to: move.to)
        }
        return nil
    }

    func getCurrentPuzzle() -> Puzzle? {
        return Puzzle(
            id: "preview",
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            moves: ["e2e4", "e7e5"],
            rating: 1500,
            themes: [],
            popularity: nil
        )
    }

    func getCurrentMoveIndex() -> Int {
        return 0
    }

    func canGoBackward() -> Bool {
        return false
    }

    func canGoForward() -> Bool {
        return false
    }

    func goBackward() -> (moveUCI: String, isPlayerMove: Bool)? {
        return nil
    }

    func goForward() -> (moveUCI: String, isPlayerMove: Bool)? {
        return nil
    }
}


// Preview wrapper that provides safe defaults
private struct PreviewWrapper: View {
    @StateObject private var viewModel: PuzzleMenuItemViewModel
    @State private var boardColor: BoardColor = .green
    @State private var boardSize: BoardSize = .medium

    init() {
        let mockPuzzleManager = MockPuzzleManager()
        _viewModel = StateObject(wrappedValue: PuzzleMenuItemViewModel(
            puzzleManager: mockPuzzleManager
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
