import Foundation

public enum BoardSize: String, CaseIterable {
    case large = "Large"
    case medium = "Medium"
    case small = "Small"

    public var size: CGFloat {
        switch self {
        case .large:
            return 400
        case .medium:
            return 300
        case .small:
            return 200
        }
    }

    static var `default`: BoardSize {
        return .medium
    }

    public static func load() -> BoardSize {
        if let sizeString = UserDefaults.standard.string(forKey: "boardSize"),
           let size = BoardSize(rawValue: sizeString) {
            print("[DEBUG] BoardSize.load - found in UserDefaults: \(sizeString) -> \(size.rawValue) (\(size.size)px)")
            return size
        }
        let defaultSize = BoardSize.default
        print("[DEBUG] BoardSize.load - not found in UserDefaults, using default: \(defaultSize.rawValue) (\(defaultSize.size)px)")
        return defaultSize
    }

    public func save() {
        print("[DEBUG] BoardSize.save - saving: \(self.rawValue) to UserDefaults key 'boardSize'")
        UserDefaults.standard.set(self.rawValue, forKey: "boardSize")
        // Verify it was saved
        if let saved = UserDefaults.standard.string(forKey: "boardSize") {
            print("[DEBUG] BoardSize.save - verified saved value: \(saved)")
        } else {
            print("[DEBUG] BoardSize.save - WARNING: value not found after saving!")
        }
    }
}

