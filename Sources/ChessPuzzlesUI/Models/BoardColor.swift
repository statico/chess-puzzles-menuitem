import Foundation
import AppKit
import SwiftUI

public enum BoardColor: String, CaseIterable {
    case green = "Green"
    case brown = "Brown"
    case blue = "Blue"
    case gray = "Gray"

    var lightSquareColor: NSColor {
        switch self {
        case .green:
            // Chess.com green theme light square
            return NSColor(red: 0.82, green: 0.93, blue: 0.82, alpha: 1.0) // #D1EDD1
        case .brown:
            // Chess.com brown/wood theme light square
            return NSColor(red: 0.96, green: 0.96, blue: 0.86, alpha: 1.0) // #F5F5DC
        case .blue:
            // Chess.com blue theme light square
            return NSColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1.0) // #EDF2F9
        case .gray:
            // Chess.com gray theme light square
            return NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0) // #F5F5F5
        }
    }

    var darkSquareColor: NSColor {
        switch self {
        case .green:
            // Chess.com green theme dark square
            return NSColor(red: 0.47, green: 0.71, blue: 0.47, alpha: 1.0) // #78B578
        case .brown:
            // Chess.com brown/wood theme dark square
            return NSColor(red: 0.76, green: 0.60, blue: 0.42, alpha: 1.0) // #C29B6B
        case .blue:
            // Chess.com blue theme dark square
            return NSColor(red: 0.47, green: 0.65, blue: 0.85, alpha: 1.0) // #78A6D9
        case .gray:
            // Chess.com gray theme dark square
            return NSColor(red: 0.76, green: 0.76, blue: 0.76, alpha: 1.0) // #C2C2C2
        }
    }

    var lightSquareSwiftUIColor: Color {
        switch self {
        case .green:
            return Color(red: 0.82, green: 0.93, blue: 0.82)
        case .brown:
            return Color(red: 0.96, green: 0.96, blue: 0.86)
        case .blue:
            return Color(red: 0.93, green: 0.95, blue: 0.98)
        case .gray:
            return Color(red: 0.96, green: 0.96, blue: 0.96)
        }
    }

    var darkSquareSwiftUIColor: Color {
        switch self {
        case .green:
            return Color(red: 0.47, green: 0.71, blue: 0.47)
        case .brown:
            return Color(red: 0.76, green: 0.60, blue: 0.42)
        case .blue:
            return Color(red: 0.47, green: 0.65, blue: 0.85)
        case .gray:
            return Color(red: 0.76, green: 0.76, blue: 0.76)
        }
    }

    static var `default`: BoardColor {
        return .green
    }

    public static func load() -> BoardColor {
        if let colorString = UserDefaults.standard.string(forKey: "boardColor"),
           let color = BoardColor(rawValue: colorString) {
            return color
        }
        return .default
    }

    public func save() {
        UserDefaults.standard.set(self.rawValue, forKey: "boardColor")
    }
}

