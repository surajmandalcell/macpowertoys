import OnePlusUI
import SwiftUI

/// A drag inside one reorderable stack: the rows' rest frames in the stack's space, the dragged row, and how
/// far the pointer moved. Only the first `movable` rows (the saved ones) take part. Pure, so it is unit tested.
struct PortmanDrag: Equatable {
    var frames: [Int: CGRect] = [:]
    var source: Int?
    var translation: CGFloat = 0

    /// Where the dragged row lands: the count of other movable rows whose middle sits above its middle.
    func target(movable: Int) -> Int? {
        guard let source, source < movable, let frame = frames[source] else { return nil }
        let center = frame.midY + translation
        return (0..<movable).filter { $0 != source && (frames[$0]?.midY ?? .infinity) < center }.count
    }

    /// The dragged row follows the pointer; the rows between its start and its target slide one slot to make room.
    func offset(of index: Int, movable: Int, spacing: CGFloat) -> CGFloat {
        guard let source, let target = target(movable: movable), let height = frames[source]?.height else { return 0 }
        if index == source { return translation }
        let slot = height + spacing
        if source < target, index > source, index <= target { return -slot }
        if target < source, index >= target, index < source { return slot }
        return 0
    }

    /// The middle of the drop line: the gap above the landing slot. Nil while the row would land where it started.
    func indicator(movable: Int, spacing: CGFloat) -> CGFloat? {
        guard let source, let target = target(movable: movable), target != source,
              let height = frames[source]?.height, let landing = frames[target] else { return nil }
        return (target > source ? landing.maxY - height : landing.minY) - spacing / 2
    }
}

/// A vertical stack whose first `movable` rows reorder by dragging anywhere on the row. Rows follow the pointer
/// only while dragged (never on hover); the others slide to make room and a line marks the drop. VoiceOver gets
/// Move up and Move down. A plain in-window drag gesture, not a drag session, so the menu panel stays open.
/// `slot` draws behind each rest position and stays put while rows slide, such as a card's guide line.
struct PortmanReorderStack<Item: Identifiable, Row: View, Slot: View>: View {
    let items: [Item]
    let movable: Int
    var spacing: CGFloat = 0
    var lineInsets = EdgeInsets()
    let name: (Item) -> String
    let move: (Item, Int) -> Void
    @ViewBuilder let row: (Item, Int) -> Row
    @ViewBuilder var slot: (Int) -> Slot

    /// Set only by snapshot tests, which render one frame of a drag.
    @State var drag = PortmanDrag()
    @State private var space = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(items) { item in
                let index = items.firstIndex { $0.id == item.id } ?? 0
                reorderable(row(item, index), item: item, index: index)
            }
        }
        .coordinateSpace(.named(space))
        .overlay(alignment: .topLeading) { line }
    }

    private var slide: Animation? { reduceMotion ? nil : OnePlusMotion.animation(PortmanForwardMetrics.reorderSlide) }

    private func reorderable(_ content: Row, item: Item, index: Int) -> some View {
        let canMove = index < movable && movable > 1
        let lifted = drag.source == index
        return content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frame in
                if drag.source == nil { drag.frames[index] = frame }
            }
            .background {
                if lifted {
                    RoundedRectangle(cornerRadius: OnePlusLinearMetrics.listRadius).fill(OnePlusLinearColor.fillGroup)
                        .shadow(color: OnePlusLinearColor.fillTileShadow, radius: PortmanForwardMetrics.liftShadowRadius,
                                y: PortmanForwardMetrics.liftShadowY)
                }
            }
            .offset(y: drag.offset(of: index, movable: movable, spacing: spacing))
            .animation(lifted ? nil : slide, value: drag.target(movable: movable))
            .background { slot(index) }
            .zIndex(lifted ? 1 : 0)
            .gesture(dragGesture(index: index, item: item), including: canMove ? .all : .subviews)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name(item))
            .accessibilityActions {
                if canMove, index > 0 { Button("Move up") { move(item, index - 1) } }
                if canMove, index < movable - 1 { Button("Move down") { move(item, index + 1) } }
            }
            .accessibilityHint(canMove ? "Drag, or use Move up and Move down, to change the order of \(name(item))" : "")
    }

    private func dragGesture(index: Int, item: Item) -> some Gesture {
        DragGesture(minimumDistance: PortmanForwardMetrics.dragStart, coordinateSpace: .named(space))
            .onChanged { value in
                if drag.source == nil { drag.source = index }
                guard drag.source == index else { return }
                drag.translation = value.translation.height
            }
            .onEnded { _ in
                guard drag.source == index else { return }
                let target = drag.target(movable: movable)
                withAnimation(slide) {
                    drag.source = nil
                    drag.translation = 0
                    if let target, target != index { move(item, target) }
                }
            }
    }

    @ViewBuilder private var line: some View {
        // Drawn over the rows, so it stays visible across the lifted row.
        if let y = drag.indicator(movable: movable, spacing: spacing) {
            Capsule().fill(OnePlusLinearColor.accent)
                .frame(height: PortmanForwardMetrics.dropLine)
                .padding(lineInsets)
                .offset(y: max(0, y - PortmanForwardMetrics.dropLine / 2))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension PortmanReorderStack where Slot == EmptyView {
    init(items: [Item], movable: Int, spacing: CGFloat = 0, lineInsets: EdgeInsets = EdgeInsets(),
         name: @escaping (Item) -> String, move: @escaping (Item, Int) -> Void, drag: PortmanDrag = PortmanDrag(),
         @ViewBuilder row: @escaping (Item, Int) -> Row) {
        self.init(items: items, movable: movable, spacing: spacing, lineInsets: lineInsets, name: name, move: move,
                  row: row, slot: { _ in EmptyView() }, drag: drag)
    }
}
