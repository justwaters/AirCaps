import ApplicationServices

public func isAXTrusted() -> Bool {
    AXIsProcessTrusted()
}

/// Triggers the OS-native Accessibility permission prompt. Side-effecting —
/// call explicitly (e.g. from a user-initiated action), not from every check.
public func requestAXTrust() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    AXIsProcessTrustedWithOptions(options as CFDictionary)
}
