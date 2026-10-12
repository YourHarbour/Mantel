import AppKit
import ApplicationServices

/// One status item belonging to some running application.
struct MenuBarItem: Equatable, Sendable {
    let appName: String
    let bundleID: String
    let pid: pid_t
    let title: String
    let frame: CGRect

    /// Stable-ish identity across rescans: an app rarely has two extras with the same title.
    var key: String { "\(bundleID)|\(title)" }

    var label: String { title.isEmpty ? appName : "\(appName) — \(title)" }

    static func == (a: MenuBarItem, b: MenuBarItem) -> Bool { a.key == b.key }
}

/// Reads and rearranges the menu bar through the accessibility API.
///
/// macOS 26 hosts every third-party status item inside the Control Center process, so
/// `CGWindowListCopyWindowInfo` no longer reports them individually — it returns a handful of
/// aggregate windows all owned by "Control Centre". The accessibility API still exposes them
/// per-app through `AXExtrasMenuBar`, which is what this uses. That needs the Accessibility
/// permission, the same one Bartender and Ice ask for.
enum MenuBarScanner {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The identity TCC actually keys the accessibility grant on. Worth showing in the UI: this
    /// app is ad-hoc signed, so the hash changes on every rebuild and the grant stops applying —
    /// the row stays ticked in System Settings while `AXIsProcessTrusted()` reports false.
    static func signingIdentity() -> String {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return "读不到签名" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let dictionary = info as? [String: Any],
              let unique = dictionary[kSecCodeInfoUnique as String] as? Data
        else { return "读不到签名" }
        return unique.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Reading

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Every status item we can see, left to right.
    static func scan() -> [MenuBarItem] {
        guard isTrusted else { return [] }
        var items: [MenuBarItem] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited, !app.isTerminated else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard let extras = attribute(element, kAXExtrasMenuBarAttribute),
                  let children = attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
            else { continue }

            for child in children {
                guard let rect = frame(of: child), rect.width > 0 else { continue }
                let title = (attribute(child, kAXTitleAttribute) as? String)
                    ?? (attribute(child, kAXDescriptionAttribute) as? String) ?? ""
                items.append(MenuBarItem(appName: app.localizedName ?? "?",
                                         bundleID: app.bundleIdentifier ?? "\(app.processIdentifier)",
                                         pid: app.processIdentifier,
                                         title: title,
                                         frame: rect))
            }
        }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Rearranging

    /// Command-dragging a status item is how a person reorders the menu bar by hand; this is the
    /// same gesture, synthesised. Posting these events also requires the Accessibility permission.
    static func commandDrag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, start)
        usleep(60_000)
        post(.leftMouseDown, start)
        usleep(120_000)

        let steps = 24
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y))
            usleep(12_000)
        }
        usleep(80_000)
        post(.leftMouseUp, end)
        usleep(120_000)
    }

    /// Drags items until the menu bar matches `desired` (left to right).
    /// Rescans between moves because every drag shifts everything else along.
    static func apply(order desired: [String], progress: (String) -> Void) {
        guard isTrusted else { return }
        for (index, key) in desired.enumerated() {
            let current = scan()
            guard let from = current.firstIndex(where: { $0.key == key }) else { continue }
            guard from != index, index < current.count else { continue }
            let item = current[from]
            let target = current[index]
            progress("移动 \(item.label)")
            // Aim just past the item currently occupying the slot, so the drop lands on its side.
            let destinationX = from > index ? target.frame.minX + 2 : target.frame.maxX - 2
            commandDrag(from: CGPoint(x: item.frame.midX, y: item.frame.midY),
                        to: CGPoint(x: destinationX, y: item.frame.midY))
        }
    }
}
