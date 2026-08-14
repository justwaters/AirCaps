import AppKit
import ApplicationServices
import Foundation

func axAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var val: CFTypeRef?
    AXUIElementCopyAttributeValue(el, attr as CFString, &val)
    return val
}

func axPress(_ el: AXUIElement) {
    AXUIElementPerformAction(el, kAXPressAction as CFString)
}

func axFind(_ el: AXUIElement, matching descOrTitle: String) -> AXUIElement? {
    let desc = axAttr(el, kAXDescriptionAttribute) as? String ?? ""
    let title = axAttr(el, kAXTitleAttribute) as? String ?? ""
    let combined = (desc + " " + title).trimmingCharacters(in: .whitespaces)
    if combined == descOrTitle || desc == descOrTitle || title == descOrTitle {
        return el
    }
    if let kids = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for kid in kids {
            if let found = axFind(kid, matching: descOrTitle) { return found }
        }
    }
    return nil
}

func axFindAll(_ el: AXUIElement, role: String) -> [AXUIElement] {
    let r = axAttr(el, kAXRoleAttribute) as? String ?? ""
    var results: [AXUIElement] = []
    if r == role { results.append(el) }
    if let kids = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for kid in kids { results += axFindAll(kid, role: role) }
    }
    return results
}

/// Short code -> Control Center checkbox label. "AT" is labeled "Adaptive" in
/// Control Center (not "Adaptive Transparency" — that label was a README typo).
public let kNoiseModeNames = [
    "ANC": "Noise Cancellation",
    "AT": "Adaptive",
    "TR": "Transparency",
]

/// Drives Control Center's Sound popover via the Accessibility API to switch
/// AirPods noise mode. Does not prompt for or exit on missing Accessibility
/// trust — callers should check `isAXTrusted()` (and call `requestAXTrust()`
/// explicitly if appropriate) before invoking this from a long-running process.
@discardableResult
public func setNoiseMode(_ shortName: String) -> Result<String, CoreError> {
    guard isAXTrusted() else { return .failure(.axNotTrusted) }

    guard let targetMode = kNoiseModeNames[shortName] else {
        return .failure(.unknownNoiseMode(shortName))
    }

    guard let cc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
        return .failure(.controlCenterNotFound)
    }

    let axApp = AXUIElementCreateApplication(cc.processIdentifier)

    guard let soundBtn = axFind(axApp, matching: "Sound") else {
        return .failure(.soundItemNotFound)
    }

    axPress(soundBtn)

    var popoverWindow: AXUIElement?
    for _ in 0..<60 {
        Thread.sleep(forTimeInterval: 0.05)
        if let windows = axAttr(axApp, kAXWindowsAttribute) as? [AXUIElement] {
            for w in windows {
                let subrole = axAttr(w, kAXSubroleAttribute) as? String ?? ""
                if subrole == "AXSystemDialog" {
                    popoverWindow = w
                    break
                }
            }
        }
        if popoverWindow != nil { break }
    }

    guard let window = popoverWindow else {
        return .failure(.popoverTimeout)
    }

    let triangles = axFindAll(window, role: "AXDisclosureTriangle")
    guard let triangle = triangles.first else {
        return .failure(.disclosureTriangleNotFound)
    }

    let triVal = axAttr(triangle, kAXValueAttribute)
    let isExpanded: Bool
    if let b = triVal as? Bool { isExpanded = b }
    else if let i = triVal as? Int { isExpanded = i != 0 }
    else { isExpanded = false }

    if !isExpanded {
        axPress(triangle)
        Thread.sleep(forTimeInterval: 0.1)
    }

    guard let targetCheckbox = axFind(window, matching: targetMode) else {
        return .failure(.checkboxNotFound(targetMode))
    }

    axPress(targetCheckbox)
    Thread.sleep(forTimeInterval: 0.05)

    axPress(soundBtn)

    return .success(targetMode)
}
