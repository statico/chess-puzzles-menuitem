import Foundation

enum BoardSize: String, CaseIterable {
    case large = "Large"
    case medium = "Medium"
    case small = "Small"

    var size: CGFloat {
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

    static func load() -> BoardSize {
        if let sizeString = UserDefaults.standard.string(forKey: "boardSize"),
           let size = BoardSize(rawValue: sizeString) {
            return size
        }
        return .default
    }

    func save() {
        UserDefaults.standard.set(self.rawValue, forKey: "boardSize")
    }
}

