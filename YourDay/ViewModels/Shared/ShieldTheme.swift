import UIKit

/// UIKit palette aligned with `LightTheme` / Tasks tab (`Todoview`, `TodoListItemView`).
enum ShieldTheme {
    static let primary = UIColor(hex: "#7BC9A6")
    static let secondary = UIColor(hex: "#F97316")
    static let destructive = UIColor(hex: "#EF4444")
    static let background = UIColor(hex: "#FFFBFA")
    static let secondaryBackground = UIColor(hex: "#FFF8F5")
    static let text = UIColor(hex: "#1F2937")
    static let secondaryText = UIColor(hex: "#6B7280")
    static let mintAccent = UIColor(hex: "#A7E2CD")
    static let peachAccent = UIColor(hex: "#FCE6D3")
    static let trackMint = UIColor(hex: "#CDEDDD")
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 31, 41, 55)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
