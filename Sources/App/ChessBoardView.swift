import AppKit

protocol ChessBoardViewDelegate: AnyObject {
    func chessBoardView(_ view: ChessBoardView, didMakeMove from: ChessEngine.Square, to: ChessEngine.Square)
    func chessBoardView(_ view: ChessBoardView, shouldHighlightSquare square: ChessEngine.Square) -> Bool
}

class ChessBoardView: NSView {
    weak var delegate: ChessBoardViewDelegate?
    var engine: ChessEngine?

    private(set) var selectedSquare: ChessEngine.Square?
    private var draggedPiece: (piece: ChessEngine.Piece, square: ChessEngine.Square)?
    private var dragOffset: NSPoint = .zero
    private var highlightedSquares: Set<ChessEngine.Square> = []

    private let lightSquareColor = NSColor(red: 0.96, green: 0.96, blue: 0.86, alpha: 1.0)
    private let darkSquareColor = NSColor(red: 0.76, green: 0.60, blue: 0.42, alpha: 1.0)
    private let selectedSquareColor = NSColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.6)
    private let highlightColor = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 0.4)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.darkGray.cgColor
    }

    func setEngine(_ engine: ChessEngine) {
        self.engine = engine
        needsDisplay = true
    }

    func highlightSquares(_ squares: Set<ChessEngine.Square>) {
        highlightedSquares = squares
        needsDisplay = true
    }

    func clearSelection() {
        selectedSquare = nil
        highlightedSquares.removeAll()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let engine = engine else { return }

        let squareSize = min(bounds.width, bounds.height) / 8

        // Draw board
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = ChessEngine.Square(file: file, rank: rank)
                let rect = NSRect(
                    x: CGFloat(file) * squareSize,
                    y: CGFloat(7 - rank) * squareSize,
                    width: squareSize,
                    height: squareSize
                )

                // Choose square color
                let isLight = (rank + file) % 2 == 0
                let baseColor = isLight ? lightSquareColor : darkSquareColor

                // Apply selection highlight
                if let selected = selectedSquare, selected == square {
                    selectedSquareColor.setFill()
                } else if highlightedSquares.contains(square) {
                    highlightColor.setFill()
                } else {
                    baseColor.setFill()
                }

                NSBezierPath(rect: rect).fill()

                // Draw piece
                if let piece = engine.getPiece(at: square),
                   square != draggedPiece?.square {
                    drawPiece(piece, in: rect)
                }
            }
        }

        // Draw dragged piece on top
        if let dragged = draggedPiece {
            let squareSize = min(bounds.width, bounds.height) / 8
            let rect = NSRect(
                x: draggedPieceLocation.x - squareSize / 2,
                y: draggedPieceLocation.y - squareSize / 2,
                width: squareSize,
                height: squareSize
            )
            drawPiece(dragged.piece, in: rect)
        }
    }

    private func drawPiece(_ piece: ChessEngine.Piece, in rect: NSRect) {
        let pieceSymbol: String
        switch piece {
        case .whiteKing: pieceSymbol = "♔"
        case .whiteQueen: pieceSymbol = "♕"
        case .whiteRook: pieceSymbol = "♖"
        case .whiteBishop: pieceSymbol = "♗"
        case .whiteKnight: pieceSymbol = "♘"
        case .whitePawn: pieceSymbol = "♙"
        case .blackKing: pieceSymbol = "♚"
        case .blackQueen: pieceSymbol = "♛"
        case .blackRook: pieceSymbol = "♜"
        case .blackBishop: pieceSymbol = "♝"
        case .blackKnight: pieceSymbol = "♞"
        case .blackPawn: pieceSymbol = "♟"
        case .empty: return
        }

        let color = piece.isWhite ? NSColor.white : NSColor.black
        let font = NSFont.systemFont(ofSize: rect.height * 0.8)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attributedString = NSAttributedString(string: pieceSymbol, attributes: attributes)
        let stringSize = attributedString.size()
        let point = NSPoint(
            x: rect.midX - stringSize.width / 2,
            y: rect.midY - stringSize.height / 2
        )
        attributedString.draw(at: point)
    }

    private func squareAt(point: NSPoint) -> ChessEngine.Square? {
        let squareSize = min(bounds.width, bounds.height) / 8
        let file = Int(point.x / squareSize)
        let rank = 7 - Int(point.y / squareSize)

        guard file >= 0 && file < 8 && rank >= 0 && rank < 8 else {
            return nil
        }

        return ChessEngine.Square(file: file, rank: rank)
    }

    private var draggedPieceLocation: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let square = squareAt(point: location),
              let engine = engine,
              let piece = engine.getPiece(at: square) else {
            return
        }

        let pieceColor: ChessEngine.Color = piece.isWhite ? .white : .black
        guard pieceColor == engine.getActiveColor() else { return }

        selectedSquare = square
        draggedPiece = (piece, square)
        draggedPieceLocation = location
        dragOffset = NSPoint(
            x: location.x - CGFloat(square.file) * (min(bounds.width, bounds.height) / 8) - (min(bounds.width, bounds.height) / 16),
            y: location.y - CGFloat(7 - square.rank) * (min(bounds.width, bounds.height) / 8) - (min(bounds.width, bounds.height) / 16)
        )

        // Highlight legal moves
        if let delegate = delegate {
            var legalSquares: Set<ChessEngine.Square> = []
            for rank in 0..<8 {
                for file in 0..<8 {
                    let testSquare = ChessEngine.Square(file: file, rank: rank)
                    if delegate.chessBoardView(self, shouldHighlightSquare: testSquare) {
                        legalSquares.insert(testSquare)
                    }
                }
            }
            highlightSquares(legalSquares)
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggedPiece != nil else { return }
        draggedPieceLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard draggedPiece != nil,
              let fromSquare = selectedSquare else {
            draggedPiece = nil
            selectedSquare = nil
            needsDisplay = true
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if let toSquare = squareAt(point: location), toSquare != fromSquare {
            delegate?.chessBoardView(self, didMakeMove: fromSquare, to: toSquare)
        }

        draggedPiece = nil
        selectedSquare = nil
        clearSelection()
        needsDisplay = true
    }
}

