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

