import SwiftUI

struct PointingHandCursorModifier: ViewModifier {
    let enabled: Bool
    @State private var isActive = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            let shouldActivate = enabled && hovering
            if shouldActivate && !isActive {
                NSCursor.pointingHand.push()
                isActive = true
            } else if !shouldActivate && isActive {
                NSCursor.pop()
                isActive = false
            }
        }
        .onDisappear {
            if isActive {
                NSCursor.pop()
                isActive = false
            }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(enabled: enabled))
    }
}

