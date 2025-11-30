import Foundation

public struct Puzzle: Codable, Identifiable {
    public let id: String
    public let fen: String
    public let moves: [String] // UCI format moves
    public let rating: Int
    public let themes: [String]
    public let popularity: Int?

    public init(id: String, fen: String, moves: [String], rating: Int, themes: [String], popularity: Int?) {
        self.id = id
        self.fen = fen
        self.moves = moves
        self.rating = rating
        self.themes = themes
        self.popularity = popularity
    }

    enum CodingKeys: String, CodingKey {
        case id = "PuzzleId"
        case fen = "FEN"
        case moves = "Moves"
        case rating = "Rating"
        case themes = "Themes"
        case popularity = "Popularity"
    }
}

public struct PuzzleStats: Codable {
    public var currentStreak: Int = 0
    public var totalSolved: Int = 0
    public var userRating: Int = 1500
    private var solveTimesData: [String: TimeInterval] = [:]
    public var lastPuzzleDate: Date?

    public init() {}

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

