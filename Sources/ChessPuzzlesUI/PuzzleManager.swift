import Foundation

// Protocol for database loading to avoid zstd dependency in UI target
public protocol PuzzleDatabaseLoader {
    func loadCachedPuzzles() -> [Puzzle]?
}

public enum Difficulty: String, CaseIterable {
    case easiest = "Easiest"
    case easier = "Easier"
    case normal = "Normal"
    case harder = "Harder"
    case hardest = "Hardest"

    func ratingRange(userRating: Int) -> ClosedRange<Int> {
        switch self {
        case .easiest:
            return (userRating - 400)...(userRating - 200)
        case .easier:
            return (userRating - 200)...(userRating - 100)
        case .normal:
            return (userRating - 100)...(userRating + 100)
        case .harder:
            return (userRating + 100)...(userRating + 200)
        case .hardest:
            return (userRating + 200)...(userRating + 400)
        }
    }
}

public class PuzzleManager {
    public static let shared = PuzzleManager()

    private var puzzles: [Puzzle] = []
    private var currentPuzzle: Puzzle?
    private var currentPuzzleIndex: Int = 0
    private var solutionMoves: [String] = []
    private var currentMoveIndex: Int = 0
    private var moveHistory: [(moveUCI: String, isPlayerMove: Bool)] = []
    private var currentHistoryIndex: Int = -1
    private var difficulty: Difficulty = .normal
    private var userRating: Int = 1500
    private var databaseLoader: PuzzleDatabaseLoader?

    private init() {
        loadUserRating()
        loadDifficulty()
    }

    public func setDatabaseLoader(_ loader: PuzzleDatabaseLoader?) {
        self.databaseLoader = loader
    }

    public func loadPuzzles() {
        // Try to load from cache first using the database loader if available
        if let loader = databaseLoader,
           let cached = loader.loadCachedPuzzles() {
            self.puzzles = cached
            return
        }

        // If no cache, we'll need to download
        // For now, use empty array - download will be triggered by UI
    }

    public func setDifficulty(_ difficulty: Difficulty) {
        self.difficulty = difficulty
        UserDefaults.standard.set(difficulty.rawValue, forKey: "puzzleDifficulty")
    }

    public func getDifficulty() -> Difficulty {
        return difficulty
    }

    func setUserRating(_ rating: Int) {
        self.userRating = rating
        UserDefaults.standard.set(rating, forKey: "userPuzzleRating")
    }

    func getUserRating() -> Int {
        return userRating
    }

    private func loadDifficulty() {
        if let difficultyString = UserDefaults.standard.string(forKey: "puzzleDifficulty"),
           let diff = Difficulty(rawValue: difficultyString) {
            self.difficulty = diff
        }
    }

    private func loadUserRating() {
        let stats = StatsManager.shared.getStats()
        self.userRating = stats.userRating
    }

    func getNextPuzzle() -> Puzzle? {
        let ratingRange = difficulty.ratingRange(userRating: userRating)
        let filteredPuzzles = puzzles.filter { ratingRange.contains($0.rating) }

        guard !filteredPuzzles.isEmpty else {
            // If no puzzles match, try to get any puzzle
            guard !puzzles.isEmpty else { return nil }
            currentPuzzle = puzzles.randomElement()
            setupCurrentPuzzle()
            return currentPuzzle
        }

        currentPuzzle = filteredPuzzles.randomElement()
        setupCurrentPuzzle()
        return currentPuzzle
    }

    private func setupCurrentPuzzle() {
        guard let puzzle = currentPuzzle else { return }
        solutionMoves = puzzle.moves
        currentMoveIndex = 0
        moveHistory = []
        currentHistoryIndex = -1
        print("[DEBUG] PuzzleManager.setupCurrentPuzzle - reset move history, solutionMoves count: \(solutionMoves.count)")
    }

    public func getCurrentPuzzle() -> Puzzle? {
        return currentPuzzle
    }

    func validateMove(_ moveUCI: String) -> Bool {
        guard currentMoveIndex < solutionMoves.count else { return false }
        let expectedMove = solutionMoves[currentMoveIndex]
        return moveUCI.lowercased() == expectedMove.lowercased()
    }

    func advanceToNextMove() {
        guard currentMoveIndex < solutionMoves.count else {
            print("[DEBUG] PuzzleManager.advanceToNextMove - already at end, currentMoveIndex: \(currentMoveIndex), solutionMoves count: \(solutionMoves.count)")
            return
        }

        let moveUCI = solutionMoves[currentMoveIndex]
        let isPlayerMove = isPlayerTurn()

        // Add to history
        moveHistory.append((moveUCI: moveUCI, isPlayerMove: isPlayerMove))
        currentHistoryIndex = moveHistory.count - 1

        currentMoveIndex += 1

        print("[DEBUG] PuzzleManager.advanceToNextMove - added move \(moveUCI) (isPlayer: \(isPlayerMove)), currentMoveIndex: \(currentMoveIndex), historyIndex: \(currentHistoryIndex)")
    }

    public func isPuzzleComplete() -> Bool {
        return currentMoveIndex >= solutionMoves.count
    }

    func getHint() -> String? {
        guard currentMoveIndex < solutionMoves.count else { return nil }
        return solutionMoves[currentMoveIndex]
    }

    func getSolution() -> [String] {
        return solutionMoves
    }

    func getCurrentMoveIndex() -> Int {
        return currentMoveIndex
    }

    public func setPuzzles(_ puzzles: [Puzzle]) {
        self.puzzles = puzzles
    }

    // Get the player's color (the side that responds to the opponent's move)
    // In Lichess format, FEN shows position before opponent's move, so player is opposite color
    func getPlayerColor() -> ChessEngine.Color? {
        guard let puzzle = currentPuzzle else { return nil }
        let components = puzzle.fen.components(separatedBy: " ")
        // FEN shows position before opponent's move, so player is the opposite color
        if components.count > 1 && components[1] == "b" {
            return .white  // If FEN says black to move, opponent is black, so player is white
        }
        return .black  // If FEN says white to move, opponent is white, so player is black
    }

    // Check if it's the player's turn to move
    // In Lichess format: opponent moves first (index 0), player responds (index 1), etc.
    // So player moves on odd indices (1, 3, 5, ...), opponent on even (0, 2, 4, ...)
    func isPlayerTurn() -> Bool {
        return currentMoveIndex % 2 == 1
    }

    // Get the next opponent/engine move (the move at the current index if it's opponent's turn)
    func getNextEngineMove() -> String? {
        guard currentMoveIndex < solutionMoves.count else { return nil }
        return solutionMoves[currentMoveIndex]
    }

    // Get the opponent's last move for highlighting
    // Returns the squares (from, to) of the last opponent move, or nil if no opponent move yet
    func getOpponentLastMove() -> (from: ChessEngine.Square, to: ChessEngine.Square)? {
        // Opponent moves on even indices (0, 2, 4, ...)
        // The last opponent move would be at the highest even index < currentMoveIndex
        // But since we advance after making moves, if currentMoveIndex is odd, the last opponent move was at currentMoveIndex - 1
        // If currentMoveIndex is even, the last opponent move was at currentMoveIndex - 2

        let lastOpponentIndex: Int
        if currentMoveIndex % 2 == 0 {
            // Currently opponent's turn, so last opponent move was 2 moves ago
            lastOpponentIndex = currentMoveIndex - 2
        } else {
            // Currently player's turn, so last opponent move was 1 move ago
            lastOpponentIndex = currentMoveIndex - 1
        }

        guard lastOpponentIndex >= 0 && lastOpponentIndex < solutionMoves.count else {
            return nil
        }

        let moveUCI = solutionMoves[lastOpponentIndex]
        guard let move = ChessEngine.Move(fromUCI: moveUCI) else {
            return nil
        }

        return (from: move.from, to: move.to)
    }

    // Navigation methods
    func canGoBackward() -> Bool {
        let result = currentHistoryIndex > 0
        print("[DEBUG] PuzzleManager.canGoBackward - returning \(result), currentHistoryIndex: \(currentHistoryIndex)")
        return result
    }

    func canGoForward() -> Bool {
        // Can go forward if there are more moves in history that have been played
        let result = currentHistoryIndex < moveHistory.count - 1
        print("[DEBUG] PuzzleManager.canGoForward - returning \(result), currentHistoryIndex: \(currentHistoryIndex), historyCount: \(moveHistory.count)")
        return result
    }

    func goBackward() -> (moveUCI: String, isPlayerMove: Bool)? {
        guard canGoBackward() else {
            print("[DEBUG] PuzzleManager.goBackward - cannot go backward, currentHistoryIndex: \(currentHistoryIndex)")
            return nil
        }

        currentHistoryIndex -= 1
        let move = moveHistory[currentHistoryIndex]

        // Update currentMoveIndex: undo one move
        // currentMoveIndex points to the next move to make, so going back means decreasing it
        currentMoveIndex = max(0, currentMoveIndex - 1)

        print("[DEBUG] PuzzleManager.goBackward - moved to historyIndex: \(currentHistoryIndex), move: \(move.moveUCI), currentMoveIndex: \(currentMoveIndex)")
        return move
    }

    func goForward() -> (moveUCI: String, isPlayerMove: Bool)? {
        guard canGoForward() else {
            print("[DEBUG] PuzzleManager.goForward - cannot go forward, currentHistoryIndex: \(currentHistoryIndex), historyCount: \(moveHistory.count)")
            return nil
        }

        currentHistoryIndex += 1
        let move = moveHistory[currentHistoryIndex]

        // Update currentMoveIndex: replay one move
        // currentMoveIndex points to the next move to make, so going forward means increasing it
        currentMoveIndex += 1

        print("[DEBUG] PuzzleManager.goForward - moved to historyIndex: \(currentHistoryIndex), move: \(move.moveUCI), currentMoveIndex: \(currentMoveIndex)")
        return move
    }

    func getHistoryPosition() -> Int {
        return currentHistoryIndex
    }

    func getHistoryCount() -> Int {
        return moveHistory.count
    }

    func getMovesUpToHistoryIndex() -> [String] {
        guard currentHistoryIndex >= 0 else { return [] }
        return Array(moveHistory[0...currentHistoryIndex].map { $0.moveUCI })
    }
}

