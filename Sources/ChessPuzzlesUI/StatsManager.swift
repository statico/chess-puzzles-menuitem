import Foundation

class StatsManager {
    static let shared = StatsManager()

    private let userDefaults = UserDefaults.standard
    private let statsKey = "puzzleStats"

    private init() {}

    func loadStats() -> PuzzleStats {
        guard let data = userDefaults.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(PuzzleStats.self, from: data) else {
            return PuzzleStats()
        }
        return stats
    }

    func saveStats(_ stats: PuzzleStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        userDefaults.set(data, forKey: statsKey)
    }

    func recordSolve(time: TimeInterval, wasCorrect: Bool) {
        var stats = loadStats()

        if wasCorrect {
            stats.currentStreak += 1
            stats.totalSolved += 1
            stats.solveTimes[Date()] = time
            stats.lastPuzzleDate = Date()

            // Update user rating (simple Elo-like adjustment)
            // For puzzles, we adjust based on solve time relative to puzzle difficulty
            // This is a simplified version
            let ratingChange = calculateRatingChange(solveTime: time)
            stats.userRating = max(800, min(3000, stats.userRating + ratingChange))
        } else {
            stats.currentStreak = 0
        }

        saveStats(stats)
    }

    private func calculateRatingChange(solveTime: TimeInterval) -> Int {
        // Simple heuristic: faster solves = better performance
        // Adjust rating by ±10-30 points based on solve time
        // This is a placeholder - a real system would use puzzle rating
        if solveTime < 30 {
            return 15 // Fast solve
        } else if solveTime < 60 {
            return 5 // Medium solve
        } else {
            return -5 // Slow solve
        }
    }

    func resetStreak() {
        var stats = loadStats()
        stats.currentStreak = 0
        saveStats(stats)
    }

    func getStats() -> PuzzleStats {
        return loadStats()
    }
}

