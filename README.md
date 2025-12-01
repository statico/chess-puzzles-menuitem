# Chess Puzzles Menu Item

A macOS menu bar application that provides chess puzzles from the Lichess database. Solve puzzles directly from your menu bar with an interactive chess board, timer, and statistics tracking. The app downloads and caches puzzle data locally for offline use.

<img width="429" height="679" alt="CleanShot 2025-11-30 at 20 45 36@2x" src="https://github.com/user-attachments/assets/b8a1d943-8852-46dc-8ffc-b873fad51efb" />

Vibe coded with [Cursor](https://cursor.com).

## Features

- Daily chess puzzles from the Lichess puzzle database
- Interactive chess board with move validation
- Puzzle difficulty levels and statistics tracking
- Timer for puzzle solving sessions
- Customizable board colors
- Offline puzzle database with automatic updates

## Development

Build the project:

```bash
make build
```

Run the app directly:

```bash
make run
```

Build the app bundle for testing:

```bash
make app
```

This creates `Chess Puzzles.app` in the project root. The build script extracts the version from `Package.swift`, creates the app bundle structure, generates the app icon, and signs the app with ad hoc signing.

## Releasing

1. Update the version in `Package.swift`:
   ```swift
   let version = "1.0.0"  // Update to new version
   ```

2. Build the release app bundle:
   ```bash
   make app
   ```

3. Test the app bundle to ensure it works correctly.

4. For distribution outside the App Store, you may need to:
   - Sign with a Developer ID certificate (replace ad hoc signing in `build-app.sh`)
   - Notarize the app with Apple
   - Create a disk image or zip archive for distribution

5. Create a git tag for the release:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

## License

This software is released into the public domain under the [Unlicense](LICENSE). The source code is under Unlicense because it was generated with [Cursor](https://cursor.com).

## Attribution

The chess piece and board square vector graphics are from [JohnPablok's improved Cburnett chess set](https://opengameart.org/content/chess-pieces-and-board-squares) and are licensed under [CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
