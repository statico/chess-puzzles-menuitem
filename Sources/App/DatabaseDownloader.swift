import Foundation
import zstd
import ChessPuzzlesUI

public class DatabaseDownloader: NSObject, URLSessionDownloadDelegate, PuzzleDatabaseLoader {
    public static let shared = DatabaseDownloader()

    private var downloadProgress: ((Int64, Int64) -> Void)?
    private var downloadCompletion: ((Result<[Puzzle], Error>) -> Void)?
    private var expectedSize: Int64 = 0

    private let databaseURL = URL(string: "https://database.lichess.org/lichess_db_puzzle.csv.zst")!
    private let localDatabaseURL: URL
    private let cachedZstFileURL: URL
    private let cacheDirectory: URL

    override private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("ChessPuzzles", isDirectory: true)

        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        self.cacheDirectory = appDirectory
        self.localDatabaseURL = appDirectory.appendingPathComponent("puzzles.json")
        self.cachedZstFileURL = appDirectory.appendingPathComponent("lichess_db_puzzle.csv.zst")
        super.init()
    }

    public func needsRefresh() -> Bool {
        guard let lastRefresh = UserDefaults.standard.object(forKey: "lastDatabaseRefresh") as? Date else {
            return true
        }
        let daysSinceRefresh = Calendar.current.dateComponents([.day], from: lastRefresh, to: Date()).day ?? 0
        return daysSinceRefresh >= 7
    }

    public func downloadDatabase(progress: @escaping (Int64, Int64) -> Void, completion: @escaping (Result<[Puzzle], Error>) -> Void) {
        // Check if cached file exists
        if FileManager.default.fileExists(atPath: cachedZstFileURL.path) {
            print("[DEBUG] Using cached zstd file: \(cachedZstFileURL.path)")
            if let attributes = try? FileManager.default.attributesOfItem(atPath: cachedZstFileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                print("[DEBUG] Cached file size: \(fileSize) bytes (\(String(format: "%.2f", Double(fileSize) / 1_000_000)) MB)")
                progress(fileSize, fileSize)
            }

            // Process cached file
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = try? Data(contentsOf: self.cachedZstFileURL) else {
                    print("[DEBUG] Failed to read cached file, will re-download")
                    self.downloadFromNetwork(progress: progress, completion: completion)
                    return
                }

                self.parseCSV(data: data, progress: { parseProgress in
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: self.cachedZstFileURL.path),
                       let fileSize = attributes[.size] as? Int64 {
                        let estimatedBytes = Int64(Double(fileSize) * parseProgress)
                        progress(estimatedBytes, fileSize)
                    }
                }, completion: completion)
            }
            return
        }

        // File doesn't exist, download it
        downloadFromNetwork(progress: progress, completion: completion)
    }

    private func downloadFromNetwork(progress: @escaping (Int64, Int64) -> Void, completion: @escaping (Result<[Puzzle], Error>) -> Void) {
        print("[DEBUG] Starting database download from: \(databaseURL)")

        self.downloadProgress = progress
        self.downloadCompletion = completion

        // Get expected file size from HEAD request first
        let headTask = URLSession.shared.dataTask(with: URLRequest(url: databaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let size = Int64(contentLength) {
                self?.expectedSize = size
                print("[DEBUG] Expected file size: \(size) bytes (\(Double(size) / 1_000_000) MB)")
                DispatchQueue.main.async {
                    progress(0, size)
                }
            } else {
                DispatchQueue.main.async {
                    progress(0, 1)
                }
            }
        }
        headTask.resume()

        // Create URLSession with delegate for progress tracking
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: databaseURL)
        task.resume()
    }

    // URLSessionDownloadDelegate methods
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async { [weak self] in
            if let progress = self?.downloadProgress {
                if totalBytesExpectedToWrite > 0 {
                    progress(totalBytesWritten, totalBytesExpectedToWrite)
                } else if self?.expectedSize ?? 0 > 0 {
                    progress(totalBytesWritten, self?.expectedSize ?? 1)
                } else {
                    progress(totalBytesWritten, totalBytesWritten + 1)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        print("[DEBUG] Download complete, file saved to: \(location.path)")

        // Move downloaded file to cache directory
        do {
            // Remove old cached file if it exists
            if FileManager.default.fileExists(atPath: cachedZstFileURL.path) {
                try FileManager.default.removeItem(at: cachedZstFileURL)
            }
            // Move new file to cache
            try FileManager.default.moveItem(at: location, to: cachedZstFileURL)
            print("[DEBUG] File cached to: \(cachedZstFileURL.path)")
        } catch {
            print("[DEBUG] Failed to cache file: \(error.localizedDescription), using temp file")
        }

        let finalLocation = FileManager.default.fileExists(atPath: cachedZstFileURL.path) ? cachedZstFileURL : location

        if let attributes = try? FileManager.default.attributesOfItem(atPath: finalLocation.path),
           let fileSize = attributes[.size] as? Int64 {
            print("[DEBUG] File size: \(fileSize) bytes (\(String(format: "%.2f", Double(fileSize) / 1_000_000)) MB)")

            // Update progress to 100%
            if let progress = downloadProgress {
                if expectedSize > 0 {
                    progress(expectedSize, expectedSize)
                } else {
                    progress(fileSize, fileSize)
                }
            }
        }

        // Read the downloaded file
        guard let data = try? Data(contentsOf: finalLocation) else {
            print("[DEBUG] Failed to read downloaded file")
            DispatchQueue.main.async {
                self.downloadCompletion?(.failure(NSError(domain: "DatabaseDownloader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to read downloaded file"])))
            }
            return
        }

        print("[DEBUG] Read \(data.count) bytes from file")
        print("[DEBUG] First 100 bytes (hex): \(data.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " "))")

        // Parse CSV data
        self.parseCSV(data: data, progress: { [weak self] parseProgress in
            // Convert parse progress to bytes (approximate)
            if let progress = self?.downloadProgress {
                let estimatedBytes = Int64(Double(data.count) * parseProgress)
                progress(estimatedBytes, Int64(data.count))
            }
        }, completion: { [weak self] result in
            self?.downloadCompletion?(result)
        })
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[DEBUG] Download error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.downloadCompletion?(.failure(error))
            }
        }
    }

    private func parseCSV(data: Data, progress: @escaping (Double) -> Void, completion: @escaping (Result<[Puzzle], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            print("[DEBUG] Starting CSV parsing, data size: \(data.count) bytes")
            var puzzles: [Puzzle] = []

            // Check if data is zstd compressed (magic bytes: 28 B5 2F FD)
            // The magic bytes might not be at the start - check first 32 bytes
            let zstdMagic = Data([0x28, 0xB5, 0x2F, 0xFD])
            var isZstd = false
            var zstdStartIndex = 0

            // Check first 32 bytes for zstd magic
            for i in 0..<min(32, data.count - 3) {
                if data.subdata(in: i..<i+4) == zstdMagic {
                    isZstd = true
                    zstdStartIndex = i
                    print("[DEBUG] Found zstd magic bytes at offset \(i)")
                    break
                }
            }

            var dataToParse = data

            if isZstd {
                print("[DEBUG] File appears to be zstd compressed. Decompressing from offset \(zstdStartIndex)...")
                // Extract only the zstd portion starting from the magic bytes
                let dataToDecompress = data.subdata(in: zstdStartIndex..<data.count)

                // Try multiple decompression approaches
                var decompressed = false

                // Approach 1: Try using streaming decompression from file
                if FileManager.default.fileExists(atPath: self.cachedZstFileURL.path) {
                    do {
                        print("[DEBUG] Trying streaming decompression from file...")
                        guard let inputStream = InputStream(url: self.cachedZstFileURL) else {
                            throw NSError(domain: "DatabaseDownloader", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot open file for streaming"])
                        }
                        let outputStream = OutputStream(toMemory: ())
                        inputStream.open()
                        outputStream.open()

                        // Skip the header bytes
                        var headerBuffer = [UInt8](repeating: 0, count: zstdStartIndex)
                        if zstdStartIndex > 0 {
                            let bytesRead = inputStream.read(&headerBuffer, maxLength: zstdStartIndex)
                            print("[DEBUG] Skipped \(bytesRead) header bytes")
                        }

                        try ZStd.decompress(src: inputStream, dst: outputStream)

                        inputStream.close()
                        outputStream.close()

                        guard let decompressedData = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
                            throw NSError(domain: "DatabaseDownloader", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to get decompressed data"])
                        }

                        dataToParse = decompressedData
                        print("[DEBUG] Streaming decompression successful. Decompressed size: \(dataToParse.count) bytes (\(String(format: "%.2f", Double(dataToParse.count) / 1_000_000)) MB)")
                        decompressed = true
                    } catch {
                        print("[DEBUG] Streaming decompression failed: \(error.localizedDescription)")
                    }
                }

                // Approach 2: Try decompressing from the magic bytes offset
                if !decompressed {
                    do {
                        print("[DEBUG] Trying decompression from offset \(zstdStartIndex)...")
                        dataToParse = try ZStd.decompress(dataToDecompress)
                        print("[DEBUG] Decompression successful from offset. Decompressed size: \(dataToParse.count) bytes (\(String(format: "%.2f", Double(dataToParse.count) / 1_000_000)) MB)")
                        decompressed = true
                    } catch {
                        print("[DEBUG] Decompression from offset failed: \(error.localizedDescription)")
                    }
                }

                // Approach 3: Try decompressing the whole file (library might handle headers)
                if !decompressed {
                    do {
                        print("[DEBUG] Trying to decompress whole file...")
                        dataToParse = try ZStd.decompress(data)
                        print("[DEBUG] Whole file decompression successful. Decompressed size: \(dataToParse.count) bytes")
                        decompressed = true
                    } catch {
                        print("[DEBUG] Whole file decompression failed: \(error.localizedDescription)")
                    }
                }

                if !decompressed {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "DatabaseDownloader", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress zstd file. The file format may not be supported."])))
                    }
                    return
                }
            } else {
                let firstBytes = data.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " ")
                print("[DEBUG] File does not appear to be zstd compressed (first 4 bytes: \(firstBytes))")
            }

            // Try to decode as UTF-8
            guard let csvString = String(data: dataToParse, encoding: .utf8) else {
                print("[DEBUG] Failed to decode as UTF-8. Trying other encodings...")

                // Try other encodings
                if let csvString = String(data: data, encoding: .utf16) {
                    print("[DEBUG] Successfully decoded as UTF-16")
                    self.parseCSVString(csvString, progress: progress, completion: completion, puzzles: &puzzles)
                    return
                }

                if let csvString = String(data: data, encoding: .ascii) {
                    print("[DEBUG] Successfully decoded as ASCII")
                    self.parseCSVString(csvString, progress: progress, completion: completion, puzzles: &puzzles)
                    return
                }

                print("[DEBUG] Failed to decode with any encoding")
                print("[DEBUG] First 200 bytes as hex: \(data.prefix(200).map { String(format: "%02x", $0) }.joined(separator: " "))")
                print("[DEBUG] First 200 bytes as ASCII (attempt): \(String(data: data.prefix(200), encoding: .ascii) ?? "N/A")")

                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "DatabaseDownloader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode CSV: file may be compressed or in unsupported encoding"])))
                }
                return
            }

            print("[DEBUG] Successfully decoded as UTF-8, string length: \(csvString.count)")
            self.parseCSVString(csvString, progress: progress, completion: completion, puzzles: &puzzles)
        }
    }

    private func parseCSVString(_ csvString: String, progress: @escaping (Double) -> Void, completion: @escaping (Result<[Puzzle], Error>) -> Void, puzzles: inout [Puzzle]) {
        let lines = csvString.components(separatedBy: .newlines)
        let totalLines = lines.count
        print("[DEBUG] Total lines in CSV: \(totalLines)")

        if totalLines > 0 {
            print("[DEBUG] First line (header): \(lines[0])")
            if totalLines > 1 {
                print("[DEBUG] Second line (sample): \(lines[1].prefix(200))")
            }
        }

        var parseErrors = 0
        for (index, line) in lines.enumerated() {
            if index == 0 {
                print("[DEBUG] Skipping header line")
                continue // Skip header
            }
            if line.isEmpty { continue }

            // Handle CSV with quoted fields - simple approach: split by comma but handle quotes
            var components: [String] = []
            var currentField = ""
            var inQuotes = false

            for char in line {
                if char == "\"" {
                    inQuotes.toggle()
                } else if char == "," && !inQuotes {
                    components.append(currentField)
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }
            components.append(currentField) // Add last field

            guard components.count >= 7 else {
                if index < 10 {
                    print("[DEBUG] Line \(index) has only \(components.count) components, skipping. Line: \(line.prefix(100))")
                }
                parseErrors += 1
                continue
            }

            let puzzleId = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let fen = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let movesStr = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let rating = Int(components[3].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1500
            let popularity = components.count > 5 ? Int(components[5].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            let themesStr = components.count > 6 ? components[6].trimmingCharacters(in: .whitespacesAndNewlines) : ""

            // Parse moves (space-separated UCI moves)
            let moves = movesStr.components(separatedBy: " ").filter { !$0.isEmpty }

            // Parse themes (space-separated)
            let themes = themesStr.components(separatedBy: " ").filter { !$0.isEmpty }

            let puzzle = Puzzle(
                id: puzzleId,
                fen: fen,
                moves: moves,
                rating: rating,
                themes: themes,
                popularity: popularity
            )

            puzzles.append(puzzle)

            if index % 1000 == 0 {
                let progressValue = Double(index) / Double(totalLines)
                DispatchQueue.main.async {
                    progress(progressValue)
                }
            }
        }

        print("[DEBUG] Parsing complete. Parsed \(puzzles.count) puzzles, \(parseErrors) errors")

        // Save to local cache
        let finalPuzzles = puzzles
        self.savePuzzlesToCache(finalPuzzles)

        DispatchQueue.main.async {
            UserDefaults.standard.set(Date(), forKey: "lastDatabaseRefresh")
            completion(.success(finalPuzzles))
        }
    }

    public func loadCachedPuzzles() -> [Puzzle]? {
        guard let data = try? Data(contentsOf: localDatabaseURL),
              let puzzles = try? JSONDecoder().decode([Puzzle].self, from: data) else {
            return nil
        }
        return puzzles
    }

    private func savePuzzlesToCache(_ puzzles: [Puzzle]) {
        guard let data = try? JSONEncoder().encode(puzzles) else { return }
        try? data.write(to: localDatabaseURL)
    }

    public func refreshDatabase(progress: @escaping (Int64, Int64) -> Void, completion: @escaping (Result<[Puzzle], Error>) -> Void) {
        downloadDatabase(progress: progress, completion: completion)
    }
}

