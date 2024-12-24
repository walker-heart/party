import SwiftUI

struct Theme {
    struct Colors {
        // MARK: - Background Colors
        static func background(_ colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? 
                Color(red: 0.11, green: 0.11, blue: 0.12) : 
                Color(red: 0.98, green: 0.98, blue: 0.98)
        }
        
        // MARK: - Surface Colors
        static func surfaceLight(_ colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? 
                Color(red: 0.17, green: 0.17, blue: 0.18) : 
                Color(red: 0.95, green: 0.95, blue: 0.95)
        }
        
        // MARK: - Text Colors
        static func textPrimary(_ colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .white : Color(red: 0.1, green: 0.1, blue: 0.1)
        }
        
        static func textSecondary(_ colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color.white.opacity(0.7) : Color(red: 0.4, green: 0.4, blue: 0.4)
        }
        
        // MARK: - Static Colors
        static let primary = Color(red: 0.2, green: 0.5, blue: 1.0)
        static let error = Color.red
        static let success = Color.green
        static let warning = Color.orange
    }
    
    struct Spacing {
        static let tiny: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    struct CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let extraLarge: CGFloat = 16
    }
    
    struct Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.3)
    }
}

// MARK: - View Extensions

extension View {
    func standardBackground(_ colorScheme: ColorScheme) -> some View {
        self.background(Theme.Colors.background(colorScheme))
    }
    
    func surfaceBackground(_ colorScheme: ColorScheme) -> some View {
        self.background(Theme.Colors.surfaceLight(colorScheme))
    }
    
    func primaryTextColor(_ colorScheme: ColorScheme) -> some View {
        self.foregroundColor(Theme.Colors.textPrimary(colorScheme))
    }
    
    func secondaryTextColor(_ colorScheme: ColorScheme) -> some View {
        self.foregroundColor(Theme.Colors.textSecondary(colorScheme))
    }
} 