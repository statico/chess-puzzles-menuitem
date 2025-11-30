import Foundation

// Basic chess engine for move validation and game state
public class ChessEngine {
    enum Piece: Character {
        case whitePawn = "P"
        case whiteRook = "R"
        case whiteKnight = "N"
        case whiteBishop = "B"
        case whiteQueen = "Q"
        case whiteKing = "K"
        case blackPawn = "p"
        case blackRook = "r"
        case blackKnight = "n"
        case blackBishop = "b"
        case blackQueen = "q"
        case blackKing = "k"
        case empty = " "

        var isWhite: Bool {
            switch self {
            case .whitePawn, .whiteRook, .whiteKnight, .whiteBishop, .whiteQueen, .whiteKing:
                return true
            default:
                return false
            }
        }

        var isBlack: Bool {
            switch self {
            case .blackPawn, .blackRook, .blackKnight, .blackBishop, .blackQueen, .blackKing:
                return true
            default:
                return false
            }
        }
    }

    public enum Color {
        case white
        case black

        var opposite: Color {
            return self == .white ? .black : .white
        }
    }

    struct Square: Hashable {
        let file: Int // 0-7 (a-h)
        let rank: Int // 0-7 (1-8)

        init(file: Int, rank: Int) {
            self.file = file
            self.rank = rank
        }

        init?(fromUCI: String) {
            guard fromUCI.count >= 2 else { return nil }
            let chars = Array(fromUCI)
            guard chars.count >= 2 else { return nil }
            let fileChar = chars[0]
            let rankChar = chars[1]
            let fileValue = Int(fileChar.asciiValue ?? 0)
            guard fileValue >= 97 && fileValue <= 104 else { return nil } // a-h
            self.file = fileValue - 97 // a=0, b=1, etc.
            guard let rank = Int(String(rankChar)), rank >= 1 && rank <= 8 else { return nil }
            self.rank = rank - 1 // Convert 1-8 to 0-7
        }

        var uci: String {
            let fileChar = Character(UnicodeScalar(97 + file)!)
            return "\(fileChar)\(rank + 1)"
        }
    }

    struct Move {
        let from: Square
        let to: Square
        let promotion: Piece?

        init(from: Square, to: Square, promotion: Piece? = nil) {
            self.from = from
            self.to = to
            self.promotion = promotion
        }

        init?(fromUCI: String) {
            guard fromUCI.count >= 4 else { return nil }
            let chars = Array(fromUCI)
            let fromStr = String(chars[0...1])
            let toStr = String(chars[2...3])
            guard let from = Square(fromUCI: fromStr),
                  let to = Square(fromUCI: toStr) else { return nil }
            self.from = from
            self.to = to
            if chars.count > 4 {
                self.promotion = Piece(rawValue: chars[4])
            } else {
                self.promotion = nil
            }
        }

        var uci: String {
            var result = from.uci + to.uci
            if let promotion = promotion {
                result += String(promotion.rawValue).lowercased()
            }
            return result
        }
    }

    private var board: [[Piece?]]
    private var activeColor: Color
    private var castlingRights: String
    private var enPassant: String?
    private var halfmoveClock: Int
    private var fullmoveNumber: Int

    init(fen: String) {
        let components = fen.components(separatedBy: " ")
        let boardFen = components[0]
        self.activeColor = components.count > 1 && components[1] == "b" ? .black : .white
        self.castlingRights = components.count > 2 ? components[2] : "-"
        self.enPassant = components.count > 3 && components[3] != "-" ? components[3] : nil
        self.halfmoveClock = components.count > 4 ? Int(components[4]) ?? 0 : 0
        self.fullmoveNumber = components.count > 5 ? Int(components[5]) ?? 1 : 1

        // Parse board
        self.board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        let ranks = boardFen.components(separatedBy: "/")
        for (rankIndex, rank) in ranks.enumerated() {
            var fileIndex = 0
            for char in rank {
                if let num = Int(String(char)) {
                    fileIndex += num
                } else if let piece = Piece(rawValue: char) {
                    if rankIndex < 8 && fileIndex < 8 {
                        board[7 - rankIndex][fileIndex] = piece
                    }
                    fileIndex += 1
                }
            }
        }
    }

    func getPiece(at square: Square) -> Piece? {
        guard square.rank >= 0 && square.rank < 8 && square.file >= 0 && square.file < 8 else {
            return nil
        }
        return board[square.rank][square.file]
    }

    func setPiece(_ piece: Piece?, at square: Square) {
        guard square.rank >= 0 && square.rank < 8 && square.file >= 0 && square.file < 8 else {
            return
        }
        board[square.rank][square.file] = piece
    }

    func getActiveColor() -> Color {
        return activeColor
    }

    func makeMove(_ move: Move) -> Bool {
        guard let piece = getPiece(at: move.from) else { return false }

        // Check if it's the correct color's turn
        let pieceColor: Color = piece.isWhite ? .white : .black
        guard pieceColor == activeColor else { return false }

        // Make the move
        _ = getPiece(at: move.to) // Capture piece (if any)
        setPiece(nil, at: move.from)

        if let promotion = move.promotion {
            setPiece(promotion, at: move.to)
        } else {
            setPiece(piece, at: move.to)
        }

        // Update active color
        activeColor = activeColor.opposite

        return true
    }

    func getLegalMoves(from square: Square) -> [Move] {
        guard let piece = getPiece(at: square) else { return [] }
        let pieceColor: Color = piece.isWhite ? .white : .black
        guard pieceColor == activeColor else { return [] }

        var moves: [Move] = []

        // Simple move generation (basic implementation)
        for rank in 0..<8 {
            for file in 0..<8 {
                let to = Square(file: file, rank: rank)
                let move = Move(from: square, to: to)

                // Basic validation - check if destination is empty or has opponent piece
                if let targetPiece = getPiece(at: to) {
                    if (piece.isWhite && targetPiece.isWhite) || (piece.isBlack && targetPiece.isBlack) {
                        continue // Can't capture own piece
                    }
                }

                // For puzzle purposes, we'll accept moves that are in the solution
                // Full legal move generation would be more complex
                moves.append(move)
            }
        }

        return moves
    }

    func toFEN() -> String {
        var fen = ""
        for rank in (0..<8).reversed() {
            var emptyCount = 0
            for file in 0..<8 {
                if let piece = board[rank][file] {
                    if emptyCount > 0 {
                        fen += String(emptyCount)
                        emptyCount = 0
                    }
                    fen += String(piece.rawValue)
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 {
                fen += String(emptyCount)
            }
            if rank > 0 {
                fen += "/"
            }
        }

        fen += " \(activeColor == .white ? "w" : "b")"
        fen += " \(castlingRights)"
        fen += " \(enPassant ?? "-")"
        fen += " \(halfmoveClock)"
        fen += " \(fullmoveNumber)"

        return fen
    }
}

