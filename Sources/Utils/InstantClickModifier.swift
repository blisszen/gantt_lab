import SwiftUI
import AppKit

// A high-performance click modifier that completely eliminates the 500ms-1000ms delay of SwiftUI's onTapGesture(count: 2).
// Dispatches single click immediately (0ms) and detects double click if clicked within 0.35s.
struct InstantClickModifier: ViewModifier {
    var onSingleClick: () -> Void
    var onDoubleClick: () -> Void
    
    @State private var lastClickTime: TimeInterval = 0
    @State private var hasTriggeredSingle: Bool = false
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !hasTriggeredSingle && abs(val.translation.width) <= 3 && abs(val.translation.height) <= 3 {
                            hasTriggeredSingle = true
                            onSingleClick()
                        }
                    }
                    .onEnded { val in
                        hasTriggeredSingle = false
                        guard abs(val.translation.width) <= 4 && abs(val.translation.height) <= 4 else { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastClickTime < 0.35 {
                            lastClickTime = 0
                            onDoubleClick()
                        } else {
                            lastClickTime = now
                        }
                    }
            )
    }
}

extension View {
    func instantClick(onSingleClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) -> some View {
        self.modifier(InstantClickModifier(onSingleClick: onSingleClick, onDoubleClick: onDoubleClick))
    }
}
