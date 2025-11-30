import Foundation

struct Puzzle: Codable, Identifiable {
    let id: String
    let fen: String
    let moves: [String] // UCI format moves
    let rating: Int
    let themes: [String]
    let popularity: Int?

    enum CodingKeys: String, CodingKey {
        case id = "PuzzleId"
        case fen = "FEN"
        case moves = "Moves"
        case rating = "Rating"
        case themes = "Themes"
        case popularity = "Popularity"
    }
}

struct PuzzleStats: Codable {
    var currentStreak: Int = 0
    var totalSolved: Int = 0
    var userRating: Int = 1500
    private var solveTimesData: [String: TimeInterval] = [:]
    var lastPuzzleDate: Date?

    var solveTimes: [Date: TimeInterval] {
        get {
            var result: [Date: TimeInterval] = [:]
            let formatter = ISO8601DateFormatter()
            for (key, value) in solveTimesData {
                if let date = formatter.date(from: key) {
                    result[date] = value
                }
            }
            return result
        }
        set {
            let formatter = ISO8601DateFormatter()
            solveTimesData = [:]
            for (date, value) in newValue {
                solveTimesData[formatter.string(from: date)] = value
            }
        }
    }

    var averageSolveTimeThisWeek: TimeInterval {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentTimes = solveTimes.filter { $0.key >= weekAgo }.map { $0.value }
        guard !recentTimes.isEmpty else { return 0 }
        return recentTimes.reduce(0, +) / Double(recentTimes.count)
    }

    enum CodingKeys: String, CodingKey {
        case currentStreak
        case totalSolved
        case userRating
        case solveTimesData
        case lastPuzzleDate
    }
}

