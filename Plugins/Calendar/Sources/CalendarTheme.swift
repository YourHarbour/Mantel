import SwiftUI

public enum CalendarTheme {
    // Windows Accent Blue
    public static let winBlue = Color(red: 0.0, green: 0.47, blue: 0.84)
    public static let winHover = Color.primary.opacity(0.08)
    public static let winSelected = Color.primary.opacity(0.12)
    
    // Dimmed days for preceding and following months
    public static let overflowText = Color.secondary.opacity(0.4)
    public static let currentMonthText = Color.primary
    
    // Lunar text color with high contrast on both light and dark backgrounds
    public static let lunarText = Color.primary.opacity(0.75)
    public static let festivalText = Color(red: 0.85, green: 0.25, blue: 0.12)
    public static let overflowLunarText = Color.secondary.opacity(0.38)
    
    public static func accentColor(named: String) -> Color {
        switch named {
        case "Windows Blue":
            return winBlue
        case "System Accent":
            return Color.accentColor
        case "Purple":
            return Color.purple
        case "Green":
            return Color.green
        case "Orange":
            return Color.orange
        case "Red":
            return Color.red
        default:
            return winBlue
        }
    }
}
