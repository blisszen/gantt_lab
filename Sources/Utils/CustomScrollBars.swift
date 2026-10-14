import SwiftUI
import AppKit

struct HorizontalScrollBar: View {
    @Binding var offset: CGFloat
    let maxOffset: CGFloat
    let viewportWidth: CGFloat
    let totalWidth: CGFloat
    
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var dragStartOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let knobWidth = max(40.0, totalWidth > 0 ? min(trackWidth, (viewportWidth / totalWidth) * trackWidth) : trackWidth)
            let maxKnobTravel = max(1.0, trackWidth - knobWidth)
            let knobProgress = maxOffset > 0 ? min(1.0, max(0.0, offset / maxOffset)) : 0.0
            let knobX = knobProgress * maxKnobTravel
            
            ZStack(alignment: .leading) {
                // Background Track
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard maxOffset > 0, maxKnobTravel > 0 else { return }
                        let clickRatio = (location.x - knobWidth / 2) / maxKnobTravel
                        let target = clickRatio * maxOffset
                        withAnimation(.easeOut(duration: 0.15)) {
                            offset = min(maxOffset, max(0, target))
                        }
                    }
                
                // Draggable Knob / Thumb
                Capsule()
                    .fill(Color.secondary.opacity(isDragging ? 0.75 : (isHovering ? 0.55 : 0.35)))
                    .frame(width: knobWidth, height: isHovering || isDragging ? 10 : 8)
                    .padding(.horizontal, 2)
                    .offset(x: knobX)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                if !isDragging {
                                    isDragging = true
                                    dragStartOffset = offset
                                }
                                guard maxOffset > 0, maxKnobTravel > 0 else { return }
                                let deltaOffset = (val.translation.width / maxKnobTravel) * maxOffset
                                offset = min(maxOffset, max(0, dragStartOffset + deltaOffset))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
            .frame(height: 14)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor).opacity(0.3)),
                alignment: .top
            )
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .frame(height: 14)
    }
}

struct VerticalScrollBar: View {
    @Binding var offset: CGFloat
    let maxOffset: CGFloat
    let viewportHeight: CGFloat
    let totalHeight: CGFloat
    
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var dragStartOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height
            let knobHeight = max(40.0, totalHeight > 0 ? min(trackHeight, (viewportHeight / totalHeight) * trackHeight) : trackHeight)
            let maxKnobTravel = max(1.0, trackHeight - knobHeight)
            let knobProgress = maxOffset > 0 ? min(1.0, max(0.0, offset / maxOffset)) : 0.0
            let knobY = knobProgress * maxKnobTravel
            
            ZStack(alignment: .top) {
                // Background Track
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 14)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard maxOffset > 0, maxKnobTravel > 0 else { return }
                        let clickRatio = (location.y - knobHeight / 2) / maxKnobTravel
                        let target = clickRatio * maxOffset
                        withAnimation(.easeOut(duration: 0.15)) {
                            offset = min(maxOffset, max(0, target))
                        }
                    }
                
                // Draggable Knob / Thumb
                Capsule()
                    .fill(Color.secondary.opacity(isDragging ? 0.75 : (isHovering ? 0.55 : 0.35)))
                    .frame(width: isHovering || isDragging ? 10 : 8, height: knobHeight)
                    .padding(.vertical, 2)
                    .offset(y: knobY)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                if !isDragging {
                                    isDragging = true
                                    dragStartOffset = offset
                                }
                                guard maxOffset > 0, maxKnobTravel > 0 else { return }
                                let deltaOffset = (val.translation.height / maxKnobTravel) * maxOffset
                                offset = min(maxOffset, max(0, dragStartOffset + deltaOffset))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
            .frame(width: 14)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color(NSColor.separatorColor).opacity(0.3)),
                alignment: .leading
            )
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .frame(width: 14)
    }
}

struct VerticalSplitDivider: View {
    @Binding var paneWidth: CGFloat
    let minWidth: CGFloat = 260
    let maxWidth: CGFloat = 650
    
    @State private var dragStartWidth: CGFloat? = nil
    
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor).opacity(0.4))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { val in
                                if dragStartWidth == nil {
                                    dragStartWidth = paneWidth
                                }
                                if let start = dragStartWidth {
                                    let newW = start + val.translation.width
                                    paneWidth = min(maxWidth, max(minWidth, newW))
                                }
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
            )
    }
}

struct HorizontalSplitDivider: View {
    @Binding var paneHeight: CGFloat
    let minHeight: CGFloat = 80
    let maxHeight: CGFloat = 450
    
    @State private var dragStartHeight: CGFloat? = nil
    
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor).opacity(0.4))
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 12)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { val in
                                if dragStartHeight == nil {
                                    dragStartHeight = paneHeight
                                }
                                if let start = dragStartHeight {
                                    // Dragging upward increases bottom height, dragging downward decreases it
                                    let newH = start - val.translation.height
                                    paneHeight = min(maxHeight, max(minHeight, newH))
                                }
                            }
                            .onEnded { _ in
                                dragStartHeight = nil
                            }
                    )
            )
    }
}


