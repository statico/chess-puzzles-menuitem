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
    var animateMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil

    @State private var selectedSquare: ChessEngine.Square?
    @State private var draggedPiece: (piece: ChessEngine.Piece, square: ChessEngine.Square)?
    @State private var dragLocation: CGPoint = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var highlightedSquares: Set<ChessEngine.Square> = []
    @State private var boardColor: BoardColor = BoardColor.load()
    @State private var pieceImages: [ChessEngine.Piece: NSImage] = [:]
    @State private var animatedPiece: (piece: ChessEngine.Piece, from: ChessEngine.Square, to: ChessEngine.Square, progress: CGFloat)? = nil
    @State private var lastAnimateMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    @State private var animationTrigger: UUID = UUID()
    @State private var currentAnimateMoveString: String = ""
    var showCoordinates: Bool = true

    // Computed property to convert animateMove to string for change detection
    private var animateMoveString: String {
        animateMove != nil ? "\(animateMove!.from.uci)-\(animateMove!.to.uci)" : ""
    }

    private let selectedSquareColor = Color(red: 1.0, green: 0.9, blue: 0.0, opacity: 0.6) // Yellow
    private let highlightColor = Color(white: 0.5, opacity: 0.5) // 50% gray for move indicators
    private let opponentMoveColor = Color(red: 1.0, green: 0.9, blue: 0.0, opacity: 0.5) // Translucent yellow

    // Computed property to determine if board should be flipped (player on bottom)
    private var isFlipped: Bool {
        guard let playerColor = playerColor else {
            return false
        }
        return playerColor == .black
    }

    init(
        engine: ChessEngine? = nil,
        playerColor: ChessEngine.Color? = nil,
        showCoordinates: Bool = true,
        onMove: ((ChessEngine.Square, ChessEngine.Square) -> Void)? = nil,
        shouldHighlight: ((ChessEngine.Square, ChessEngine.Square?) -> Bool)? = nil,
        opponentLastMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil,
        animateMove: (from: ChessEngine.Square, to: ChessEngine.Square)? = nil
    ) {
        self.engine = engine
        self.playerColor = playerColor
        self.showCoordinates = showCoordinates
        self.onMove = onMove
        self.shouldHighlight = shouldHighlight
        self.opponentLastMove = opponentLastMove
        self.animateMove = animateMove
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

                // Draw dragged piece on top
                if let dragged = draggedPiece, isDragging {
                    pieceView(piece: dragged.piece, size: squareSize)
                        .position(dragLocation)
                }

                // Draw animated piece on top
                if let anim = animatedPiece {
                    // Calculate display positions - flip if needed
                    let fromDisplayFile = isFlipped ? (7 - anim.from.file) : anim.from.file
                    let fromDisplayRank = isFlipped ? (7 - anim.from.rank) : anim.from.rank
                    let toDisplayFile = isFlipped ? (7 - anim.to.file) : anim.to.file
                    let toDisplayRank = isFlipped ? (7 - anim.to.rank) : anim.to.rank

                    let fromX = CGFloat(fromDisplayFile) * squareSize + squareSize / 2
                    let fromY = CGFloat(7 - fromDisplayRank) * squareSize + squareSize / 2
                    let toX = CGFloat(toDisplayFile) * squareSize + squareSize / 2
                    let toY = CGFloat(7 - toDisplayRank) * squareSize + squareSize / 2

                    let currentX = fromX + (toX - fromX) * anim.progress
                    let currentY = fromY + (toY - fromY) * anim.progress

                    pieceView(piece: anim.piece, size: squareSize)
                        .position(x: currentX, y: currentY)
                }
            }
            .onAppear {
                loadImages()
                boardColor = BoardColor.load()
                print("[DEBUG] ChessBoardView.body.onAppear - playerColor: \(String(describing: playerColor)), isFlipped: \(isFlipped)")
                if let engine = engine {
                    print("[DEBUG] ChessBoardView.body.onAppear - activeColor: \(engine.getActiveColor())")
                }
                // Check for pending animation on appear
                let newString = animateMoveString
                if newString != currentAnimateMoveString && !newString.isEmpty {
                    print("[DEBUG] ChessBoardView.body.onAppear - detected pending animation: '\(newString)'")
                    currentAnimateMoveString = newString
                    animationTrigger = UUID()
                }
            }
            .task(id: animateMoveString) {
                print("[DEBUG] ChessBoardView.body.task - animateMoveString changed to: '\(animateMoveString)', currentAnimateMoveString: '\(currentAnimateMoveString)'")
                if animateMoveString != currentAnimateMoveString && !animateMoveString.isEmpty {
                    currentAnimateMoveString = animateMoveString
                    if animateMove != nil {
                        print("[DEBUG] ChessBoardView.body.task - triggering animation for move: \(animateMoveString)")
                        // Small delay to ensure view is ready
                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                        animationTrigger = UUID()
                    }
                }
            }
            .onChange(of: animateMove?.from.file) { _ in
                let newString = animateMoveString
                if newString != currentAnimateMoveString {
                    print("[DEBUG] ChessBoardView.onChange - animateMove.from.file changed, new string: '\(newString)'")
                    currentAnimateMoveString = newString
                    if !newString.isEmpty {
                        animationTrigger = UUID()
                    }
                }
            }
            .onChange(of: animateMove?.from.rank) { _ in
                let newString = animateMoveString
                if newString != currentAnimateMoveString {
                    print("[DEBUG] ChessBoardView.onChange - animateMove.from.rank changed, new string: '\(newString)'")
                    currentAnimateMoveString = newString
                    if !newString.isEmpty {
                        animationTrigger = UUID()
                    }
                }
            }
            .onChange(of: animateMove?.to.file) { _ in
                let newString = animateMoveString
                if newString != currentAnimateMoveString {
                    print("[DEBUG] ChessBoardView.onChange - animateMove.to.file changed, new string: '\(newString)'")
                    currentAnimateMoveString = newString
                    if !newString.isEmpty {
                        animationTrigger = UUID()
                    }
                }
            }
            .onChange(of: animateMove?.to.rank) { _ in
                let newString = animateMoveString
                if newString != currentAnimateMoveString {
                    print("[DEBUG] ChessBoardView.onChange - animateMove.to.rank changed, new string: '\(newString)'")
                    currentAnimateMoveString = newString
                    if !newString.isEmpty {
                        animationTrigger = UUID()
                    }
                }
            }
            .onChange(of: animationTrigger) { _ in
                if let move = animateMove {
                    print("[DEBUG] ChessBoardView.body.onChange - animationTrigger changed, calling checkAndStartAnimation with squareSize: \(squareSize)")
                    checkAndStartAnimation(move: move, squareSize: squareSize)
                }
            }
        }
        .background(Color(white: 0.3))
    }

    private func drawBoard(context: GraphicsContext, size: CGSize, squareSize: CGFloat) {
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = ChessEngine.Square(file: file, rank: rank)

                // Calculate display position - flip if needed
                let displayFile = isFlipped ? (7 - file) : file
                let displayRank = isFlipped ? (7 - rank) : rank

                let rect = CGRect(
                    x: CGFloat(displayFile) * squareSize,
                    y: CGFloat(7 - displayRank) * squareSize,
                    width: squareSize,
                    height: squareSize
                )

                // Choose square color (based on actual board position, not display position)
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
                    // Draw gray circle overlay for valid moves
                    let circleRadius = squareSize * 0.15 // 15% of square size
                    let circleCenter = CGPoint(x: rect.midX, y: rect.midY)
                    let circlePath = Path { path in
                        path.addEllipse(in: CGRect(
                            x: circleCenter.x - circleRadius,
                            y: circleCenter.y - circleRadius,
                            width: circleRadius * 2,
                            height: circleRadius * 2
                        ))
                    }
                    context.fill(circlePath, with: .color(highlightColor))
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

                // Skip drawing piece if it's being animated (it will be drawn separately)
                if let anim = animatedPiece {
                    if anim.from == square {
                        continue // Skip source square
                    }
                    if anim.to == square {
                        continue // Skip destination square during animation
                    }
                }

                if let piece = engine.getPiece(at: square) {
                    // Calculate display position - flip if needed
                    let displayFile = isFlipped ? (7 - file) : file
                    let displayRank = isFlipped ? (7 - rank) : rank

                    let rect = CGRect(
                        x: CGFloat(displayFile) * squareSize,
                        y: CGFloat(7 - displayRank) * squareSize,
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
        // When flipped, reverse the order (h-a instead of a-h)
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let displayFiles = isFlipped ? files.reversed() : files
        for (index, file) in displayFiles.enumerated() {
            let x = CGFloat(index) * squareSize + squareSize / 2

            let text = Text(file)
                .font(.system(size: fontSize))
                .foregroundColor(coordinateColor)

            let renderer = ImageRenderer(content: text)
            if let nsImage = renderer.nsImage {
                let textSize = nsImage.size
                // Position at bottom: size.height - textSize.height - 2 (2 pixels from bottom edge)
                let y = size.height - textSize.height - 2
                let point = CGPoint(
                    x: x - textSize.width / 2,
                    y: y
                )
                let resolvedImage = context.resolve(Image(nsImage: nsImage))
                context.draw(resolvedImage, at: point, anchor: .topLeading)
            }
        }

        // Draw rank labels (1-8) along the left edge
        // When flipped, reverse the order (8-1 instead of 1-8)
        let ranks = ["1", "2", "3", "4", "5", "6", "7", "8"]
        let displayRanks = isFlipped ? ranks.reversed() : ranks
        for (index, rank) in displayRanks.enumerated() {
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
        // Convert screen coordinates to display coordinates
        let displayFile = Int(point.x / squareSize)
        let displayRank = 7 - Int(point.y / squareSize)

        guard displayFile >= 0 && displayFile < 8 && displayRank >= 0 && displayRank < 8 else {
            return nil
        }

        // Convert display coordinates back to board coordinates if flipped
        let boardFile = isFlipped ? (7 - displayFile) : displayFile
        let boardRank = isFlipped ? (7 - displayRank) : displayRank

        return ChessEngine.Square(file: boardFile, rank: boardRank)
    }

    private func handleTap(location: CGPoint, squareSize: CGFloat, geometry: GeometryProxy) {
        guard let square = squareAt(point: location, squareSize: squareSize),
              let engine = engine else {
            // Clicked outside board or no engine - deselect
            selectedSquare = nil
            highlightedSquares.removeAll()
            return
        }

        // If a piece is already selected, check if this is a destination click
        if let fromSquare = selectedSquare {
            print("[DEBUG] ChessBoardView.handleTap - piece already selected at \(fromSquare.uci), clicked on \(square.uci)")
            print("[DEBUG] ChessBoardView.handleTap - highlightedSquares count: \(highlightedSquares.count), contains \(square.uci): \(highlightedSquares.contains(square))")
            if highlightedSquares.count > 0 {
                let highlightedList = highlightedSquares.map { $0.uci }.joined(separator: ", ")
                print("[DEBUG] ChessBoardView.handleTap - highlighted squares: \(highlightedList)")
            }

            // Check if clicking on a valid destination
            if highlightedSquares.contains(square) {
                // Valid destination - execute the move
                print("[DEBUG] ChessBoardView.handleTap - ✓ VALID DESTINATION! Executing move from \(fromSquare.uci) to \(square.uci)")
                onMove?(fromSquare, square)
                // Clear selection after move
                selectedSquare = nil
                highlightedSquares.removeAll()
                return
            } else {
                print("[DEBUG] ChessBoardView.handleTap - ✗ Not a valid destination (square \(square.uci) not in highlightedSquares)")
            }

            // Not a valid destination - check if clicking on another player's piece
            if let piece = engine.getPiece(at: square) {
                let pieceColor: ChessEngine.Color = piece.isWhite ? .white : .black

                // Check if this is a player's piece
                let isPlayerPiece: Bool
                if let playerColor = playerColor {
                    isPlayerPiece = pieceColor == playerColor
                } else {
                    let activeColor = engine.getActiveColor()
                    isPlayerPiece = pieceColor == activeColor
                }

                if isPlayerPiece {
                    // Select this new piece instead
                    print("[DEBUG] ChessBoardView.handleTap - selecting new square: \(square.uci)")
                    selectedSquare = square
                    // Clear old highlights first
                    highlightedSquares.removeAll()

                    // Highlight legal moves for new selection
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
                        if let selected = selectedSquare {
                            print("[DEBUG] ChessBoardView.handleTap - highlighted \(legalSquares.count) legal squares for \(selected.uci)")
                            if legalSquares.count > 0 {
                                let highlightedList = legalSquares.map { $0.uci }.joined(separator: ", ")
                                print("[DEBUG] ChessBoardView.handleTap - legal squares: \(highlightedList)")
                            }
                        }
                    }
                    return
                }
            }

            // Clicked on empty square or invalid destination - deselect
            print("[DEBUG] ChessBoardView.handleTap - deselecting, clicked on empty/invalid square")
            selectedSquare = nil
            highlightedSquares.removeAll()
            return
        }

        // No piece selected yet - try to select a piece
        guard let piece = engine.getPiece(at: square) else {
            // Empty square - do nothing
            return
        }

        let pieceColor: ChessEngine.Color = piece.isWhite ? .white : .black

        // If playerColor is set, only allow selecting player's pieces
        if let playerColor = playerColor {
            guard pieceColor == playerColor else {
                // Opponent's piece - do nothing
                return
            }
        } else {
            // Fallback to original behavior: only allow active color
            let activeColor = engine.getActiveColor()
            guard pieceColor == activeColor else {
                // Not active color - do nothing
                return
            }
        }

        // Select the piece
        print("[DEBUG] ChessBoardView.handleTap - selecting square: \(square.uci)")
        selectedSquare = square

        // Clear any existing highlights first
        highlightedSquares.removeAll()

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
            if let selected = selectedSquare {
                print("[DEBUG] ChessBoardView.handleTap - highlighted \(legalSquares.count) legal squares for \(selected.uci)")
                if legalSquares.count > 0 {
                    let highlightedList = legalSquares.map { $0.uci }.joined(separator: ", ")
                    print("[DEBUG] ChessBoardView.handleTap - legal squares: \(highlightedList)")
                }
            }
        }
    }

    private func handleDragChanged(value: DragGesture.Value, squareSize: CGFloat, geometry: GeometryProxy) {
        let location = value.location

        if !isDragging {
            // Start drag - track start location
            dragStartLocation = value.startLocation
            guard let square = squareAt(point: location, squareSize: squareSize),
                  let engine = engine,
                  let piece = engine.getPiece(at: square) else {
                return
            }

            let pieceColor: ChessEngine.Color = piece.isWhite ? .white : .black

            // If playerColor is set, only allow selecting player's pieces
            if let playerColor = playerColor {
                guard pieceColor == playerColor else {
                    return
                }
            } else {
                // Fallback to original behavior: only allow active color
                let activeColor = engine.getActiveColor()
                guard pieceColor == activeColor else {
                    return
                }
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
        print("[DEBUG] ChessBoardView.handleDragEnded - location: (\(value.location.x), \(value.location.y)), isFlipped: \(isFlipped), isDragging: \(isDragging)")

        // Calculate drag distance to detect taps
        let dragDistance = sqrt(pow(value.location.x - dragStartLocation.x, 2) + pow(value.location.y - dragStartLocation.y, 2))
        let isTap = dragDistance < 5.0 // Consider it a tap if moved less than 5 points

        print("[DEBUG] ChessBoardView.handleDragEnded - dragDistance: \(dragDistance), isTap: \(isTap)")

        // Clean up drag state first
        draggedPiece = nil
        isDragging = false

        // If it was a tap (minimal movement), handle as tap gesture
        if isTap {
            print("[DEBUG] ChessBoardView.handleDragEnded - detected tap, delegating to handleTap")
            handleTap(location: value.location, squareSize: squareSize, geometry: geometry)
            // Note: handleTap will manage selectedSquare and highlightedSquares
            return
        }

        // This was a drag - handle as drag move
        guard let fromSquare = selectedSquare else {
            print("[DEBUG] ChessBoardView.handleDragEnded - no selected square")
            selectedSquare = nil
            highlightedSquares.removeAll()
            return
        }

        let location = value.location
        if let toSquare = squareAt(point: location, squareSize: squareSize), toSquare != fromSquare {
            print("[DEBUG] ChessBoardView.handleDragEnded - drag move from \(fromSquare.uci) to \(toSquare.uci)")
            onMove?(fromSquare, toSquare)
        } else {
            print("[DEBUG] ChessBoardView.handleDragEnded - invalid destination square or same square")
        }

        // Clear selection after drag move
        selectedSquare = nil
        highlightedSquares.removeAll()
    }

    private func pieceView(piece: ChessEngine.Piece, size: CGFloat) -> some View {
        // Apply same padding as canvas drawing (10% padding = 0.8x size)
        let pieceSize = size * 0.8
        return Group {
            if let image = pieceImages[piece] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: pieceSize, height: pieceSize)
            } else {
                pieceSymbolView(piece: piece, size: pieceSize)
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


    private func checkAndStartAnimation(move: (from: ChessEngine.Square, to: ChessEngine.Square), squareSize: CGFloat) {
        print("[DEBUG] ChessBoardView.checkAndStartAnimation - called for move from \(move.from.uci) to \(move.to.uci)")
        // Check if this is a new move (different from last one)
        if let lastMove = lastAnimateMove,
           lastMove.from == move.from && lastMove.to == move.to {
            print("[DEBUG] ChessBoardView.checkAndStartAnimation - same move as last, skipping animation")
            return // Same move, don't animate again
        }

        print("[DEBUG] ChessBoardView.checkAndStartAnimation - new move detected, starting animation")
        lastAnimateMove = move
        startAnimation(move: move, squareSize: squareSize)
    }

    private func startAnimation(move: (from: ChessEngine.Square, to: ChessEngine.Square), squareSize: CGFloat) {
        guard let engine = engine else {
            print("[DEBUG] ChessBoardView.startAnimation - no engine")
            return
        }

        // Get piece from the current engine state (before move is made)
        guard let piece = engine.getPiece(at: move.from) else {
            print("[DEBUG] ChessBoardView.startAnimation - no piece at from square \(move.from.uci)")
            return
        }

        print("[DEBUG] ChessBoardView.startAnimation - starting animation for piece \(piece) from \(move.from.uci) to \(move.to.uci)")

        // Start animation - set initial state
        animatedPiece = (piece: piece, from: move.from, to: move.to, progress: 0.0)
        print("[DEBUG] ChessBoardView.startAnimation - animatedPiece set to progress 0.0, starting SwiftUI animation")

        // Animate the piece by updating the entire tuple with cubic ease in-out
        let animationDuration: TimeInterval = 0.25
        withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: animationDuration)) {
            animatedPiece = (piece: piece, from: move.from, to: move.to, progress: 1.0)
            print("[DEBUG] ChessBoardView.startAnimation - animatedPiece updated to progress 1.0 inside withAnimation")
        }

        // Clear animation after it fully completes (at 100%) to ensure smooth transition
        // The engine move happens at 98%, so the piece will be at destination in engine state
        // but we keep the animated piece visible until animation completes to avoid visual jump
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            print("[DEBUG] ChessBoardView.startAnimation - animation completed, clearing animatedPiece")
            self.animatedPiece = nil
            // Clear lastAnimateMove so the same move can be animated again if needed
            self.lastAnimateMove = nil
        }
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
