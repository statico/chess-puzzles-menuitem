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

        var candidateMoves: [Move] = []

        // Generate candidate moves based on piece type
        switch piece {
        case .whitePawn, .blackPawn:
            candidateMoves = generatePawnMoves(from: square, piece: piece)
        case .whiteRook, .blackRook:
            candidateMoves = generateRookMoves(from: square, piece: piece)
        case .whiteKnight, .blackKnight:
            candidateMoves = generateKnightMoves(from: square, piece: piece)
        case .whiteBishop, .blackBishop:
            candidateMoves = generateBishopMoves(from: square, piece: piece)
        case .whiteQueen, .blackQueen:
            candidateMoves = generateQueenMoves(from: square, piece: piece)
        case .whiteKing, .blackKing:
            candidateMoves = generateKingMoves(from: square, piece: piece)
        case .empty:
            return []
        }

        // Filter out moves that leave the king in check
        var legalMoves: [Move] = []
        for move in candidateMoves {
            if isMoveLegal(move: move) {
                legalMoves.append(move)
            }
        }

        return legalMoves
    }

    private func generatePawnMoves(from square: Square, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let isWhite = piece.isWhite
        let direction = isWhite ? 1 : -1
        let startRank = isWhite ? 1 : 6

        // Move forward one square
        if square.rank + direction >= 0 && square.rank + direction < 8 {
            let forwardSquare = Square(file: square.file, rank: square.rank + direction)
            if getPiece(at: forwardSquare) == nil {
                // Promotion on last rank
                if (isWhite && forwardSquare.rank == 7) || (!isWhite && forwardSquare.rank == 0) {
                    moves.append(Move(from: square, to: forwardSquare, promotion: isWhite ? .whiteQueen : .blackQueen))
                } else {
                    moves.append(Move(from: square, to: forwardSquare))
                }
            }
        }

        // Move forward two squares from starting position
        if square.rank == startRank {
            let twoForwardSquare = Square(file: square.file, rank: square.rank + direction * 2)
            if getPiece(at: twoForwardSquare) == nil && getPiece(at: Square(file: square.file, rank: square.rank + direction)) == nil {
                moves.append(Move(from: square, to: twoForwardSquare))
            }
        }

        // Capture diagonally
        for fileOffset in [-1, 1] {
            if square.file + fileOffset >= 0 && square.file + fileOffset < 8 &&
               square.rank + direction >= 0 && square.rank + direction < 8 {
                let captureSquare = Square(file: square.file + fileOffset, rank: square.rank + direction)
                if let targetPiece = getPiece(at: captureSquare) {
                    if (isWhite && targetPiece.isBlack) || (!isWhite && targetPiece.isWhite) {
                        // Promotion on capture to last rank
                        if (isWhite && captureSquare.rank == 7) || (!isWhite && captureSquare.rank == 0) {
                            moves.append(Move(from: square, to: captureSquare, promotion: isWhite ? .whiteQueen : .blackQueen))
                        } else {
                            moves.append(Move(from: square, to: captureSquare))
                        }
                    }
                }
            }
        }

        return moves
    }

    private func generateRookMoves(from square: Square, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let isWhite = piece.isWhite

        // Horizontal and vertical directions
        let directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]

        for (fileOffset, rankOffset) in directions {
            for distance in 1..<8 {
                let newFile = square.file + fileOffset * distance
                let newRank = square.rank + rankOffset * distance

                guard newFile >= 0 && newFile < 8 && newRank >= 0 && newRank < 8 else { break }

                let targetSquare = Square(file: newFile, rank: newRank)
                if let targetPiece = getPiece(at: targetSquare) {
                    if (isWhite && targetPiece.isBlack) || (!isWhite && targetPiece.isWhite) {
                        moves.append(Move(from: square, to: targetSquare))
                    }
                    break // Blocked by piece
                } else {
                    moves.append(Move(from: square, to: targetSquare))
                }
            }
        }

        return moves
    }

    private func generateKnightMoves(from square: Square, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let isWhite = piece.isWhite

        let knightMoves = [
            (2, 1), (2, -1), (-2, 1), (-2, -1),
            (1, 2), (1, -2), (-1, 2), (-1, -2)
        ]

        for (fileOffset, rankOffset) in knightMoves {
            let newFile = square.file + fileOffset
            let newRank = square.rank + rankOffset

            guard newFile >= 0 && newFile < 8 && newRank >= 0 && newRank < 8 else { continue }

            let targetSquare = Square(file: newFile, rank: newRank)
            if let targetPiece = getPiece(at: targetSquare) {
                if (isWhite && targetPiece.isBlack) || (!isWhite && targetPiece.isWhite) {
                    moves.append(Move(from: square, to: targetSquare))
                }
            } else {
                moves.append(Move(from: square, to: targetSquare))
            }
        }

        return moves
    }

    private func generateBishopMoves(from square: Square, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let isWhite = piece.isWhite

        // Diagonal directions
        let directions = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

        for (fileOffset, rankOffset) in directions {
            for distance in 1..<8 {
                let newFile = square.file + fileOffset * distance
                let newRank = square.rank + rankOffset * distance

                guard newFile >= 0 && newFile < 8 && newRank >= 0 && newRank < 8 else { break }

                let targetSquare = Square(file: newFile, rank: newRank)
                if let targetPiece = getPiece(at: targetSquare) {
                    if (isWhite && targetPiece.isBlack) || (!isWhite && targetPiece.isWhite) {
                        moves.append(Move(from: square, to: targetSquare))
                    }
                    break // Blocked by piece
                } else {
                    moves.append(Move(from: square, to: targetSquare))
                }
            }
        }

        return moves
    }

    private func generateQueenMoves(from square: Square, piece: Piece) -> [Move] {
        // Queen moves like both rook and bishop
        return generateRookMoves(from: square, piece: piece) + generateBishopMoves(from: square, piece: piece)
    }

    private func generateKingMoves(from square: Square, piece: Piece) -> [Move] {
        var moves: [Move] = []
        let isWhite = piece.isWhite

        // King can move one square in any direction
        for fileOffset in -1...1 {
            for rankOffset in -1...1 {
                if fileOffset == 0 && rankOffset == 0 { continue }

                let newFile = square.file + fileOffset
                let newRank = square.rank + rankOffset

                guard newFile >= 0 && newFile < 8 && newRank >= 0 && newRank < 8 else { continue }

                let targetSquare = Square(file: newFile, rank: newRank)
                if let targetPiece = getPiece(at: targetSquare) {
                    if (isWhite && targetPiece.isBlack) || (!isWhite && targetPiece.isWhite) {
                        moves.append(Move(from: square, to: targetSquare))
                    }
                } else {
                    moves.append(Move(from: square, to: targetSquare))
                }
            }
        }

        return moves
    }

    private func isMoveLegal(move: Move) -> Bool {
        // Make a deep copy of the board to test the move
        var originalBoard: [[Piece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        for rank in 0..<8 {
            for file in 0..<8 {
                originalBoard[rank][file] = board[rank][file]
            }
        }
        let originalActiveColor = activeColor

        // Temporarily make the move
        guard let piece = getPiece(at: move.from) else { return false }
        let _ = getPiece(at: move.to) // Capture piece (if any)
        setPiece(nil, at: move.from)
        if let promotion = move.promotion {
            setPiece(promotion, at: move.to)
        } else {
            setPiece(piece, at: move.to)
        }

        // Check if this move leaves the king in check
        let pieceColor: Color = piece.isWhite ? .white : .black
        let kingInCheck = isKingInCheck(color: pieceColor)

        // Restore board
        board = originalBoard
        activeColor = originalActiveColor

        // Move is legal if it doesn't leave the king in check
        return !kingInCheck
    }

    private func isKingInCheck(color: Color) -> Bool {
        // Find the king
        let kingPiece: Piece = color == .white ? .whiteKing : .blackKing
        var kingSquare: Square?

        for rank in 0..<8 {
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)
                if getPiece(at: square) == kingPiece {
                    kingSquare = square
                    break
                }
            }
            if kingSquare != nil { break }
        }

        guard let king = kingSquare else { return false }

        // Check if any opponent piece can attack the king
        let opponentColor: Color = color.opposite
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)
                if let piece = getPiece(at: square) {
                    let pieceColor: Color = piece.isWhite ? .white : .black
                    if pieceColor == opponentColor {
                        // Generate moves for this opponent piece and check if any can capture the king
                        let moves = generatePseudoLegalMoves(from: square, piece: piece)
                        if moves.contains(where: { $0.to == king }) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    private func generatePseudoLegalMoves(from square: Square, piece: Piece) -> [Move] {
        // Generate moves without checking for check (used for check detection)
        switch piece {
        case .whitePawn, .blackPawn:
            return generatePawnMoves(from: square, piece: piece)
        case .whiteRook, .blackRook:
            return generateRookMoves(from: square, piece: piece)
        case .whiteKnight, .blackKnight:
            return generateKnightMoves(from: square, piece: piece)
        case .whiteBishop, .blackBishop:
            return generateBishopMoves(from: square, piece: piece)
        case .whiteQueen, .blackQueen:
            return generateQueenMoves(from: square, piece: piece)
        case .whiteKing, .blackKing:
            return generateKingMoves(from: square, piece: piece)
        case .empty:
            return []
        }
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

