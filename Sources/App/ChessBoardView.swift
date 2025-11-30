import AppKit

protocol ChessBoardViewDelegate: AnyObject {
    func chessBoardView(_ view: ChessBoardView, didMakeMove from: ChessEngine.Square, to: ChessEngine.Square)
    func chessBoardView(_ view: ChessBoardView, shouldHighlightSquare square: ChessEngine.Square) -> Bool
}

class ChessBoardView: NSView {
    weak var delegate: ChessBoardViewDelegate?
    var engine: ChessEngine?
    var playerColor: ChessEngine.Color? // The color the player is playing

    private(set) var selectedSquare: ChessEngine.Square?
    private var draggedPiece: (piece: ChessEngine.Piece, square: ChessEngine.Square)?
    private var dragOffset: NSPoint = .zero
    private var highlightedSquares: Set<ChessEngine.Square> = []

    private var boardColor: BoardColor = BoardColor.load()
    private var pieceImages: [ChessEngine.Piece: NSImage] = [:]

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
        boardColor = BoardColor.load()
        loadImages()
    }

    func setBoardColor(_ color: BoardColor) {
        boardColor = color
        boardColor.save()
        needsDisplay = true
    }

    private func loadImages() {
        loadPieceImages()
    }

    private func loadPieceImages() {
        let pieces: [(ChessEngine.Piece, String)] = [
            (.whiteKing, "w_king_png_shadow_512px"),
            (.whiteQueen, "w_queen_png_shadow_512px"),
            (.whiteRook, "w_rook_png_shadow_512px"),
            (.whiteBishop, "w_bishop_png_shadow_512px"),
            (.whiteKnight, "w_knight_png_shadow_512px"),
            (.whitePawn, "w_pawn_png_shadow_512px"),
            (.blackKing, "b_king_png_shadow_512px"),
            (.blackQueen, "b_queen_png_shadow_512px"),
            (.blackRook, "b_rook_png_shadow_512px"),
            (.blackBishop, "b_bishop_png_shadow_512px"),
            (.blackKnight, "b_knight_png_shadow_512px"),
            (.blackPawn, "b_pawn_png_shadow_512px")
        ]

        for (piece, fileName) in pieces {
            if let image = loadImage(named: fileName, inDirectory: "ChessPieces") {
                pieceImages[piece] = image
            }
        }
    }


    private func loadImage(named name: String, inDirectory directory: String) -> NSImage? {
        var url: URL?

        // Swift Package Manager's .process() flattens the directory structure
        // So files are in the bundle root, not in subdirectories
        // Try without subdirectory first (flattened structure)
        if let bundleUrl = Bundle.module.url(forResource: name, withExtension: "png") {
            url = bundleUrl
        } else if let bundleUrl = Bundle.main.url(forResource: name, withExtension: "png") {
            url = bundleUrl
        } else if let resourcePath = Bundle.module.resourcePath {
            // Try root first (flattened)
            let filePath = (resourcePath as NSString).appendingPathComponent("\(name).png")
            if FileManager.default.fileExists(atPath: filePath) {
                url = URL(fileURLWithPath: filePath)
            } else {
                // Try with subdirectory (in case structure is preserved)
                let dirPath = (resourcePath as NSString).appendingPathComponent(directory)
                let filePathWithDir = (dirPath as NSString).appendingPathComponent("\(name).png")
                if FileManager.default.fileExists(atPath: filePathWithDir) {
                    url = URL(fileURLWithPath: filePathWithDir)
                }
            }
        }

        guard let fileURL = url else {
            return nil
        }

        // Load PNG image
        return NSImage(contentsOf: fileURL)
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
                let baseColor = isLight ? boardColor.lightSquareColor : boardColor.darkSquareColor
                baseColor.setFill()
                NSBezierPath(rect: rect).fill()

                // Apply selection highlight overlay
                if let selected = selectedSquare, selected == square {
                    let context = NSGraphicsContext.current
                    context?.saveGraphicsState()
                    context?.compositingOperation = .sourceOver
                    selectedSquareColor.setFill()
                    NSBezierPath(rect: rect).fill()
                    context?.restoreGraphicsState()
                } else if highlightedSquares.contains(square) {
                    let context = NSGraphicsContext.current
                    context?.saveGraphicsState()
                    context?.compositingOperation = .sourceOver
                    highlightColor.setFill()
                    NSBezierPath(rect: rect).fill()
                    context?.restoreGraphicsState()
                }

                // Draw piece
                if let piece = engine.getPiece(at: square),
                   square != draggedPiece?.square {
                    drawPiece(piece, in: rect)
                }
            }
        }

        // Draw coordinates
        drawCoordinates(squareSize: squareSize)

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

    private func drawCoordinates(squareSize: CGFloat) {
        let fontSize: CGFloat = 10
        let font = NSFont.systemFont(ofSize: fontSize)

        // Single color for all coordinates: 50% opacity black
        let coordinateColor = NSColor(white: 0.0, alpha: 0.5)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: coordinateColor
        ]

        // Draw file labels (a-h) along the bottom edge
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        for (index, file) in files.enumerated() {
            let x = CGFloat(index) * squareSize + squareSize / 2
            let y: CGFloat = 2  // Small offset from bottom
            let string = NSAttributedString(string: file, attributes: attributes)
            let stringSize = string.size()
            let point = NSPoint(
                x: x - stringSize.width / 2,
                y: y
            )
            string.draw(at: point)
        }

        // Draw rank labels (1-8) along the left edge
        let ranks = ["1", "2", "3", "4", "5", "6", "7", "8"]
        for (index, rank) in ranks.enumerated() {
            // Rank 1 is at the bottom (index 0), rank 8 is at the top (index 7)
            let y = CGFloat(7 - index) * squareSize + squareSize / 2
            let x: CGFloat = 2  // Small offset from left
            let string = NSAttributedString(string: rank, attributes: attributes)
            let stringSize = string.size()
            let point = NSPoint(
                x: x,
                y: y - stringSize.height / 2
            )
            string.draw(at: point)
        }
    }

    private func drawPiece(_ piece: ChessEngine.Piece, in rect: NSRect) {
        guard piece != .empty else { return }

        // Try to use image first
        if let image = pieceImages[piece] {
            let padding: CGFloat = rect.height * 0.1
            let imageRect = NSRect(
                x: rect.origin.x + padding,
                y: rect.origin.y + padding,
                width: rect.width - padding * 2,
                height: rect.height - padding * 2
            )
            // Use proper drawing method for NSImage
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }

        // Fallback to Unicode symbols if images not loaded
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

        // If playerColor is set, only allow selecting player's pieces
        if let playerColor = playerColor {
            guard pieceColor == playerColor else { return }
        } else {
            // Fallback to original behavior: only allow active color
            guard pieceColor == engine.getActiveColor() else { return }
        }

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

