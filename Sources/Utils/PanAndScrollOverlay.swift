import SwiftUI
import AppKit
import QuartzCore

struct PanAndScrollOverlay: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat) -> Void
    var onRightPan: (CGFloat, CGFloat) -> Void
    
    func makeNSView(context: Context) -> PanNSView {
        let view = PanNSView()
        view.onScroll = onScroll
        view.onRightPan = onRightPan
        return view
    }
    
    func updateNSView(_ nsView: PanNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onRightPan = onRightPan
    }
    
    class PanNSView: NSView {
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        var onRightPan: ((CGFloat, CGFloat) -> Void)?
        
        private var eventMonitor: Any?
        private var isRightPanning = false
        private var lastRightPos: NSPoint?
        private var hasPushedCursor = false
        
        // MARK: Display-synchronized event coalescing
        // 트랙패드/휠(120Hz+)과 우클릭 드래그 이벤트를 누적했다가 화면 갱신 주기(CADisplayLink)마다 한 번만 반영한다.
        // → 한 프레임에 여러 번 상태를 바꾸며 렌더링 대기열이 밀리는 현상을 방지.
        private var pendingScrollDx: CGFloat = 0
        private var pendingScrollDy: CGFloat = 0
        private var pendingPanDx: CGFloat = 0
        private var pendingPanDy: CGFloat = 0
        private var displayLink: CADisplayLink?
        private var idleFrameCount = 0
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                startMonitoring()
            } else {
                stopMonitoring()
                stopDisplayLink()
            }
        }
        
        private var hasPendingDeltas: Bool {
            pendingScrollDx != 0 || pendingScrollDy != 0 || pendingPanDx != 0 || pendingPanDy != 0
        }
        
        /// 다음 화면 갱신 시점에 누적된 델타를 반영하도록 예약
        private func scheduleFlush() {
            idleFrameCount = 0
            if displayLink == nil {
                // NSView.displayLink 는 이 뷰가 속한 화면의 주사율(60/120Hz)에 맞춰 호출된다. (macOS 14+)
                let link = self.displayLink(target: self, selector: #selector(onDisplayLinkTick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            displayLink?.isPaused = false
        }
        
        @objc private func onDisplayLinkTick(_ link: CADisplayLink) {
            if hasPendingDeltas {
                idleFrameCount = 0
                flushPendingDeltas()
            } else {
                // 몇 프레임 동안 입력이 없으면 일시정지하여 유휴 시 CPU 사용을 없앤다.
                idleFrameCount += 1
                if idleFrameCount > 3 {
                    link.isPaused = true
                }
            }
        }
        
        private func flushPendingDeltas() {
            if pendingScrollDx != 0 || pendingScrollDy != 0 {
                let dx = pendingScrollDx
                let dy = pendingScrollDy
                pendingScrollDx = 0
                pendingScrollDy = 0
                onScroll?(dx, dy)
            }
            if pendingPanDx != 0 || pendingPanDy != 0 {
                let dx = pendingPanDx
                let dy = pendingPanDy
                pendingPanDx = 0
                pendingPanDy = 0
                onRightPan?(dx, dy)
            }
        }
        
        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }
        
        private func startMonitoring() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .rightMouseDown, .rightMouseDragged, .rightMouseUp]) { [weak self] event in
                guard let self = self, let win = self.window, event.window == win else {
                    return event
                }
                
                // Convert mouse point to this view's local bounds
                let locInView = self.convert(event.locationInWindow, from: nil)
                let isInside = self.bounds.contains(locInView)
                
                switch event.type {
                case .scrollWheel:
                    if isInside {
                        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 16.0
                        self.pendingScrollDx += event.scrollingDeltaX * factor
                        self.pendingScrollDy += event.scrollingDeltaY * factor
                        self.scheduleFlush()
                        return nil // Cleanly consume scroll event
                    }
                    
                case .rightMouseDown:
                    if isInside {
                        self.isRightPanning = true
                        self.lastRightPos = event.locationInWindow
                        if !self.hasPushedCursor {
                            NSCursor.closedHand.push()
                            self.hasPushedCursor = true
                        }
                        return nil
                    }
                    
                case .rightMouseDragged:
                    if self.isRightPanning {
                        let currentPos = event.locationInWindow
                        if let last = self.lastRightPos {
                            let deltaX = currentPos.x - last.x
                            let deltaY = currentPos.y - last.y
                            // Accumulate pan deltas (pan right drags timeline left, so positive delta moves content left)
                            self.pendingPanDx += deltaX
                            self.pendingPanDy += deltaY
                            self.scheduleFlush()
                        }
                        self.lastRightPos = currentPos
                        return nil
                    }
                    
                case .rightMouseUp:
                    if self.isRightPanning {
                        self.isRightPanning = false
                        self.lastRightPos = nil
                        if self.hasPushedCursor {
                            NSCursor.pop()
                            self.hasPushedCursor = false
                        }
                        return nil
                    }
                    
                default:
                    break
                }
                return event
            }
        }
        
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                stopMonitoring()
                stopDisplayLink()
            }
        }
        
        private func stopMonitoring() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        
        // NEVER intercept left clicks, double clicks, button clicks, or text focus.
        // Always returning nil ensures underlying SwiftUI views receive 100% of left mouse interactions!
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}
