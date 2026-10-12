import Foundation
import Combine

public final class CalendarStateManager: ObservableObject {
    public static let shared = CalendarStateManager()
    
    private let prefix = "plugin.com.local.mantel.plugin.calendar."
    private let defaults = UserDefaults.standard
    
    public init() {}
    
    public var startOnMonday: Bool {
        get {
            if defaults.object(forKey: prefix + "startOnMonday") == nil {
                return true
            }
            return defaults.bool(forKey: prefix + "startOnMonday")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: prefix + "startOnMonday")
            NotificationCenter.default.post(name: NSNotification.Name("CalendarStateChanged"), object: nil)
        }
    }
    
    public var showLunar: Bool {
        get {
            if defaults.object(forKey: prefix + "showLunar") == nil {
                return true
            }
            return defaults.bool(forKey: prefix + "showLunar")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: prefix + "showLunar")
            NotificationCenter.default.post(name: NSNotification.Name("CalendarStateChanged"), object: nil)
        }
    }
    
    public var showFestivals: Bool {
        get {
            if defaults.object(forKey: prefix + "showFestivals") == nil {
                return true
            }
            return defaults.bool(forKey: prefix + "showFestivals")
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: prefix + "showFestivals")
            NotificationCenter.default.post(name: NSNotification.Name("CalendarStateChanged"), object: nil)
        }
    }
    
    public var accentColorName: String {
        get {
            defaults.string(forKey: prefix + "accentColorName") ?? "Windows Blue"
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: prefix + "accentColorName")
            NotificationCenter.default.post(name: NSNotification.Name("CalendarStateChanged"), object: nil)
        }
    }
}
