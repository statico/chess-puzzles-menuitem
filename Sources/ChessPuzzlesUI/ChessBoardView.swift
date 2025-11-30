import SwiftUI
import AppKit

// Helper to get the correct bundle for resources
extension Bundle {
    static var chessPuzzlesUI: Bundle {
        // For library targets, resources are in a separate bundle
        let mainBundle = Bundle.main
        if let resourceURL = mainBundle.resourceURL,
           let resourceBundle = Bundle(url: resourceURL.appendingPathComponent("chess-puzzles-menuitem_ChessPuzzlesUI.bundle")) {
            return resourceBundle
        }
        // Fallback to module bundle
        return Bundle.module
    }
}

struct ChessBoardView: View {
    var engine: ChessEngine?
    var playerColor: ChessEngine.Color?
    var onMove: ((ChessEngine.Square, ChessEngine.Square) -> Void)?
    var shouldHighlight: ((ChessEngine.Square, ChessEngine.Square?) -> Bool)?
    var opponentLastMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil

    @State private var selectedSquare: ChessEngine.Square?
    @State private var draggedPiece: (piece: ChessEngine.Piece, square: ChessEngine.Square)?
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var highlightedSquares: Set<ChessEngine.Square> = []
    @State private var boardColor: BoardColor = BoardColor.load()
    @State private var pieceImages: [ChessEngine.Piece: NSImage] = [:]
    var showCoordinates: Bool = true

    private let selectedSquareColor = Color(red: 0.5, green: 0.8, blue: 1.0, opacity: 0.6)
    private let highlightColor = Color(red: 0.2, green: 0.8, blue: 0.2, opacity: 0.4)
    private let opponentMoveColor = Color(red: 1.0, green: 0.9, blue: 0.0, opacity: 0.5) // Translucent yellow

    init(
        engine: ChessEngine? = nil,
        playerColor: ChessEngine.Color? = nil,
        showCoordinates: Bool = true,
        onMove: ((ChessEngine.Square, ChessEngine.Square) -> Void)? = nil,
        shouldHighlight: ((ChessEngine.Square, ChessEngine.Square?) -> Bool)? = nil,
        opponentLastMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    ) {
        self.engine = engine
        self.playerColor = playerColor
        self.showCoordinates = showCoordinates
        self.onMove = onMove
        self.shouldHighlight = shouldHighlight
        self.opponentLastMove = opponentLastMove
    }

    var body: some View {
        GeometryReader { geometry in
            let squareSize = min(geometry.size.width, geometry.size.height) / 8

            ZStack {
                // Draw board squares
                Canvas { context, size in
                    drawBoard(context: context, size: size, squareSize: squareSize)
                    drawPieces(context: context, size: size, squareSize: squareSize)
                    if showCoordinates {
                        drawCoordinates(context: context, size: size, squareSize: squareSize)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleDragChanged(value: value, squareSize: squareSize, geometry: geometry)
                        }
                        .onEnded { value in
                            handleDragEnded(value: value, squareSize: squareSize, geometry: geometry)
                        }
                )
                .onTapGesture { location in
                    handleTap(location: location, squareSize: squareSize, geometry: geometry)
                }

                // Draw dragged piece on top
                if let dragged = draggedPiece, isDragging {
                    pieceView(piece: dragged.piece, size: squareSize)
                        .position(dragLocation)
                }
            }
        }
        .background(Color(white: 0.3))
        .onAppear {
            loadImages()
            boardColor = BoardColor.load()
        }
        .id(engine?.toFEN() ?? UUID().uuidString)
    }

    private func drawBoard(context: GraphicsContext, size: CGSize, squareSize: CGFloat) {
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = ChessEngine.Square(file: file, rank: rank)
                let rect = CGRect(
                    x: CGFloat(file) * squareSize,
                    y: CGFloat(7 - rank) * squareSize,
                    width: squareSize,
                    height: squareSize
                )

                // Choose square color
                let isLight = (rank + file) % 2 == 0
                let baseColor = isLight ? boardColor.lightSquareSwiftUIColor : boardColor.darkSquareSwiftUIColor

                // Draw square
                context.fill(
                    Path(rect),
                    with: .color(baseColor)
                )

                // Draw opponent's last move highlight (translucent yellow) - draw first so other highlights show on top
                if let lastMove = opponentLastMove,
                   (square == lastMove.from || square == lastMove.to) {
                    context.fill(
                        Path(rect),
                        with: .color(opponentMoveColor)
                    )
                }

                // Draw selection highlight
                if let selected = selectedSquare, selected == square {
                    context.fill(
                        Path(rect),
                        with: .color(selectedSquareColor)
                    )
                } else if highlightedSquares.contains(square) {
                    context.fill(
                        Path(rect),
                        with: .color(highlightColor)
                    )
                }
            }
        }
    }

    private func drawPieces(context: GraphicsContext, size: CGSize, squareSize: CGFloat) {
        guard let engine = engine else { return }

        for rank in 0..<8 {
            for file in 0..<8 {
                let square = ChessEngine.Square(file: file, rank: rank)

                // Skip drawing piece if it's being dragged
                if let dragged = draggedPiece, dragged.square == square {
                    continue
                }

                if let piece = engine.getPiece(at: square) {
                    let rect = CGRect(
                        x: CGFloat(file) * squareSize,
                        y: CGFloat(7 - rank) * squareSize,
                width: squareSize,
                height: squareSize
            )

                    drawPiece(context: context, piece: piece, in: rect)
                }
            }
        }
    }

    private func drawPiece(context: GraphicsContext, piece: ChessEngine.Piece, in rect: CGRect) {
        guard piece != .empty else { return }

        // Try to use image first
        if let image = pieceImages[piece] {
            let padding = rect.height * 0.1
            let imageRect = CGRect(
                x: rect.origin.x + padding,
                y: rect.origin.y + padding,
                width: rect.width - padding * 2,
                height: rect.height - padding * 2
            )

            let resolvedImage = context.resolve(Image(nsImage: image))
            context.draw(resolvedImage, in: imageRect)
            return
        }

        // Fallback to Unicode symbols
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

        let color = piece.isWhite ? Color.white : Color.black
        let font = Font.system(size: rect.height * 0.8)

        let text = Text(pieceSymbol)
            .font(font)
            .foregroundColor(color)

        // Draw text using TextRenderer
        let renderer = ImageRenderer(content: text)
        renderer.scale = 2.0 // Higher resolution
        if let nsImage = renderer.nsImage {
            let textRect = CGRect(
                x: rect.midX - rect.width * 0.4,
                y: rect.midY - rect.height * 0.4,
                width: rect.width * 0.8,
                height: rect.height * 0.8
            )
            let resolvedImage = context.resolve(Image(nsImage: nsImage))
            context.draw(resolvedImage, in: textRect)
        }
    }

    private func drawCoordinates(context: GraphicsContext, size: CGSize, squareSize: CGFloat) {
        let fontSize: CGFloat = 10
        let coordinateColor = Color(white: 0.0, opacity: 0.5)

        // Draw file labels (a-h) along the bottom edge
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        for (index, file) in files.enumerated() {
            let x = CGFloat(index) * squareSize + squareSize / 2
            let y: CGFloat = 2

            let text = Text(file)
                .font(.system(size: fontSize))
                .foregroundColor(coordinateColor)

            let renderer = ImageRenderer(content: text)
            if let nsImage = renderer.nsImage {
                let textSize = nsImage.size
                let point = CGPoint(
                    x: x - textSize.width / 2,
                    y: y
                )
                let resolvedImage = context.resolve(Image(nsImage: nsImage))
                context.draw(resolvedImage, at: point, anchor: .topLeading)
            }
        }

        // Draw rank labels (1-8) along the left edge
        let ranks = ["1", "2", "3", "4", "5", "6", "7", "8"]
        for (index, rank) in ranks.enumerated() {
            let y = CGFloat(7 - index) * squareSize + squareSize / 2
            let x: CGFloat = 2

            let text = Text(rank)
                .font(.system(size: fontSize))
                .foregroundColor(coordinateColor)

            let renderer = ImageRenderer(content: text)
            if let nsImage = renderer.nsImage {
                let textSize = nsImage.size
                let point = CGPoint(
                    x: x,
                    y: y - textSize.height / 2
                )
                let resolvedImage = context.resolve(Image(nsImage: nsImage))
                context.draw(resolvedImage, at: point, anchor: .topLeading)
            }
        }
    }

    private func squareAt(point: CGPoint, squareSize: CGFloat) -> ChessEngine.Square? {
        let file = Int(point.x / squareSize)
        let rank = 7 - Int(point.y / squareSize)

        guard file >= 0 && file < 8 && rank >= 0 && rank < 8 else {
            return nil
        }

        return ChessEngine.Square(file: file, rank: rank)
    }

    private func handleTap(location: CGPoint, squareSize: CGFloat, geometry: GeometryProxy) {
        guard let square = squareAt(point: location, squareSize: squareSize),
              let engine = engine,
              let piece = engine.getPiece(at: square) else {
            selectedSquare = nil
            highlightedSquares.removeAll()
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

        // Highlight legal moves
        if let shouldHighlight = shouldHighlight {
            var legalSquares: Set<ChessEngine.Square> = []
            for rank in 0..<8 {
                for file in 0..<8 {
                    let testSquare = ChessEngine.Square(file: file, rank: rank)
                    if shouldHighlight(testSquare, selectedSquare) {
                        legalSquares.insert(testSquare)
                    }
                }
            }
            highlightedSquares = legalSquares
        }
    }

    private func handleDragChanged(value: DragGesture.Value, squareSize: CGFloat, geometry: GeometryProxy) {
        let location = value.location

        if !isDragging {
            // Start drag
            guard let square = squareAt(point: location, squareSize: squareSize),
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
            isDragging = true

            // Highlight legal moves
            if let shouldHighlight = shouldHighlight {
                var legalSquares: Set<ChessEngine.Square> = []
                for rank in 0..<8 {
                    for file in 0..<8 {
                        let testSquare = ChessEngine.Square(file: file, rank: rank)
                        if shouldHighlight(testSquare, selectedSquare) {
                            legalSquares.insert(testSquare)
                        }
                    }
                }
                highlightedSquares = legalSquares
            }
        }

        dragLocation = location
    }

    private func handleDragEnded(value: DragGesture.Value, squareSize: CGFloat, geometry: GeometryProxy) {
        guard let fromSquare = selectedSquare else {
            draggedPiece = nil
            isDragging = false
            selectedSquare = nil
            highlightedSquares.removeAll()
            return
        }

        let location = value.location
        if let toSquare = squareAt(point: location, squareSize: squareSize), toSquare != fromSquare {
            onMove?(fromSquare, toSquare)
        }

        draggedPiece = nil
        isDragging = false
        selectedSquare = nil
        highlightedSquares.removeAll()
    }

    private func pieceView(piece: ChessEngine.Piece, size: CGFloat) -> some View {
        Group {
            if let image = pieceImages[piece] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                pieceSymbolView(piece: piece, size: size)
            }
        }
    }

    private func pieceSymbolView(piece: ChessEngine.Piece, size: CGFloat) -> some View {
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
        case .empty: pieceSymbol = ""
        }
        return Text(pieceSymbol)
            .font(.system(size: size * 0.8))
            .foregroundColor(piece.isWhite ? .white : .black)
            .frame(width: size, height: size)
    }

    /// Calculates the optimal image size as an exact multiple of 512px
    /// that is >= the target display size
    private func optimalImageSize(for targetSize: CGFloat) -> CGFloat {
        // Exact multiples of 512px: 512, 256, 128, 64, 32, 16
        let multiples: [CGFloat] = [512, 256, 128, 64, 32, 16]

        // Find the smallest multiple that is >= targetSize
        for multiple in multiples {
            if multiple >= targetSize {
                return multiple
            }
        }

        // If target is smaller than 16, use 16 (smallest multiple)
        return 16
    }

    /// Resizes an NSImage to the specified size
    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        resizedImage.unlockFocus()
        return resizedImage
    }

    private func loadImages() {
        // Calculate the maximum piece display size we'll need
        // Based on the largest board size (320px) with 10% padding
        let maxBoardSize: CGFloat = 320
        let maxSquareSize = maxBoardSize / 8
        let maxPieceDisplaySize = maxSquareSize * 0.8 // 10% padding

        // Find optimal image size (exact multiple of 512px)
        let optimalSize = optimalImageSize(for: maxPieceDisplaySize)

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
            if let originalImage = loadImage(named: fileName, inDirectory: "ChessPieces") {
                // Resize to optimal size (exact multiple of 512px)
                let targetSize = NSSize(width: optimalSize, height: optimalSize)
                let resizedImage = resizeImage(originalImage, to: targetSize)
                pieceImages[piece] = resizedImage
            }
        }
    }

    private func loadImage(named name: String, inDirectory directory: String) -> NSImage? {
        var url: URL?

        // Swift Package Manager's .process() flattens the directory structure
        let resourceBundle = Bundle.chessPuzzlesUI

        if let bundleUrl = resourceBundle.url(forResource: name, withExtension: "png") {
            url = bundleUrl
        }

        if url == nil, let bundleUrl = Bundle.main.url(forResource: name, withExtension: "png") {
            url = bundleUrl
        }

        if url == nil, let resourcePath = resourceBundle.resourcePath {
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

        return NSImage(contentsOf: fileURL)
    }

    func highlightSquares(_ squares: Set<ChessEngine.Square>) {
        highlightedSquares = squares
    }

    func clearSelection() {
        selectedSquare = nil
        highlightedSquares.removeAll()
    }

    func setBoardColor(_ color: BoardColor) {
        boardColor = color
        boardColor.save()
    }
}

#Preview("Chess Board - Starting Position") {
    let engine = ChessEngine(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    return ChessBoardView(engine: engine, showCoordinates: true)
        .frame(width: 400, height: 400)
        .padding()
}

#Preview("Chess Board - Small, No Coordinates") {
    let engine = ChessEngine(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    return ChessBoardView(engine: engine, showCoordinates: false)
        .frame(width: 200, height: 200)
        .padding()
}
