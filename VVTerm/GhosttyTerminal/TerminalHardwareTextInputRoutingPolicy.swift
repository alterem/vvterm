import Foundation

enum TerminalKeyboardFocusReason {
    case explicitUserRequest
    case initialActivation
    case reconnectRestore
    case directTouch
    case selectionGesture
}

struct TerminalKeyboardFocusPolicy {
    private enum Mode {
        case typing
        case browse
    }

    private var mode: Mode = .typing
    private(set) var shouldRestoreOnReconnect = false

    var allowsAutomaticFocus: Bool {
        mode == .typing
    }

    var isBrowsing: Bool {
        mode == .browse
    }

    mutating func requestFocus(for reason: TerminalKeyboardFocusReason) -> Bool {
        switch reason {
        case .explicitUserRequest:
            mode = .typing
            shouldRestoreOnReconnect = true
            return true
        case .initialActivation, .directTouch, .selectionGesture:
            guard mode == .typing else { return false }
            shouldRestoreOnReconnect = true
            return true
        case .reconnectRestore:
            return mode == .typing && shouldRestoreOnReconnect
        }
    }

    mutating func dismissForUser() {
        mode = .browse
        shouldRestoreOnReconnect = false
    }

    mutating func markForReconnect() {
        guard mode == .typing else { return }
        shouldRestoreOnReconnect = true
    }

    mutating func clearReconnect() {
        shouldRestoreOnReconnect = false
    }
}

enum TerminalHardwareTextInputRoutingPolicy {
    static func shouldRoutePressToSystemTextInput(
        hasControlModifier: Bool,
        hasAlternateModifier: Bool,
        hasCommandModifier: Bool,
        hasActiveIMEComposition: Bool,
        isSystemTextInputToggleKey: Bool,
        hasTerminalFallbackKey: Bool,
        keyProducesText: Bool
    ) -> Bool {
        if hasControlModifier || hasAlternateModifier || hasCommandModifier {
            return false
        }
        if hasActiveIMEComposition {
            return true
        }
        if isSystemTextInputToggleKey {
            return true
        }
        if hasTerminalFallbackKey {
            return false
        }
        // Let UIKit own all remaining unmodified hardware text input so IMEs,
        // dead keys, and layout-specific composition can start reliably.
        let _ = keyProducesText
        return true
    }
}
