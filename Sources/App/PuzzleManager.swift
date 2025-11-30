import Foundation

enum Difficulty: String, CaseIterable {
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

class PuzzleManager {
    static let shared = PuzzleManager()

    private var puzzles: [Puzzle] = []
    private var currentPuzzle: Puzzle?
    private var currentPuzzleIndex: Int = 0
    private var solutionMoves: [String] = []
    private var currentMoveIndex: Int = 0
    private var difficulty: Difficulty = .normal
    private var userRating: Int = 1500

    private init() {
        loadUserRating()
        loadDifficulty()
    }

    func loadPuzzles() {
        // Try to load from cache first
        if let cached = DatabaseDownloader.shared.loadCachedPuzzles() {
            self.puzzles = cached
            return
        }

        // If no cache, we'll need to download
        // For now, use empty array - download will be triggered by UI
    }

    func setDifficulty(_ difficulty: Difficulty) {
        self.difficulty = difficulty
        UserDefaults.standard.set(difficulty.rawValue, forKey: "puzzleDifficulty")
    }

    func getDifficulty() -> Difficulty {
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
    }

    func getCurrentPuzzle() -> Puzzle? {
        return currentPuzzle
    }

    func validateMove(_ moveUCI: String) -> Bool {
        guard currentMoveIndex < solutionMoves.count else { return false }
        let expectedMove = solutionMoves[currentMoveIndex]
        return moveUCI.lowercased() == expectedMove.lowercased()
    }

    func advanceToNextMove() {
        currentMoveIndex += 1
    }

    func isPuzzleComplete() -> Bool {
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

    func setPuzzles(_ puzzles: [Puzzle]) {
        self.puzzles = puzzles
    }
}

