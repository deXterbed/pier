import CoreGraphics
import Foundation
import Testing

@testable import PierCore

/// A screen with a menu bar taken off the top.
private let visible = CGRect(x: 0, y: 0, width: 1600, height: 875)
private let card = CGSize(width: 400, height: 70)

@Suite("Placement")
struct PlacementTests {

    @Test("each edge puts the dock against that edge, inside its margin")
    func edgesHug() {
        let bottom = DockPlacement(edge: .bottom, margin: 12).frame(contentSize: card, in: visible)
        #expect(bottom.minY == visible.minY + 12)

        let top = DockPlacement(edge: .top, margin: 12).frame(contentSize: card, in: visible)
        #expect(top.maxY == visible.maxY - 12)

        let leading = DockPlacement(edge: .leading, margin: 12).frame(contentSize: card, in: visible)
        #expect(leading.minX == visible.minX + 12)

        let trailing = DockPlacement(edge: .trailing, margin: 12).frame(contentSize: card, in: visible)
        #expect(trailing.maxX == visible.maxX - 12)
    }

    @Test("alignment slides the dock along its edge")
    func alignmentMoves() {
        let centered = DockPlacement(edge: .bottom, alignment: .center)
            .frame(contentSize: card, in: visible)
        #expect(centered.midX == visible.midX)

        let start = DockPlacement(edge: .bottom, alignment: .start, margin: 12)
            .frame(contentSize: card, in: visible)
        #expect(start.minX == visible.minX + 12)

        let end = DockPlacement(edge: .bottom, alignment: .end, margin: 12)
            .frame(contentSize: card, in: visible)
        #expect(end.maxX == visible.maxX - 12)
    }

    @Test("an offset nudges it along the edge without leaving the screen")
    func offsetStaysOnScreen() {
        let placement = DockPlacement(edge: .bottom, alignment: .center, offsetAlongEdge: 99999)
        let frame = placement.frame(contentSize: card, in: visible)
        #expect(frame.maxX <= visible.maxX)
        #expect(frame.minX >= visible.minX)
    }

    @Test("edges decide orientation; only a floating dock gets a say")
    func orientationFollowsEdge() {
        #expect(DockPlacement(edge: .bottom).orientation == .horizontal)
        #expect(DockPlacement(edge: .top).orientation == .horizontal)
        #expect(DockPlacement(edge: .leading).orientation == .vertical)
        #expect(DockPlacement(edge: .trailing).orientation == .vertical)
        #expect(DockPlacement(edge: .floating, floatingOrientation: .vertical).orientation == .vertical)
    }

    @Test("a floating dock sits where it was put, and centres if it never was")
    func floatingRemembers() {
        let placed = DockPlacement(edge: .floating, freePosition: CGPoint(x: 200, y: 300))
        #expect(placed.frame(contentSize: card, in: visible).origin == CGPoint(x: 200, y: 300))

        let fresh = DockPlacement(edge: .floating)
        #expect(fresh.frame(contentSize: card, in: visible).midX == visible.midX)
    }

    @Test("hiding leaves by the docked edge and keeps the other axis put")
    func hidingGoesTheRightWay() {
        for edge in [DockEdge.top, .bottom, .leading, .trailing] {
            let placement = DockPlacement(edge: edge)
            let shown = placement.frame(contentSize: card, in: visible)
            let hidden = placement.hiddenFrame(contentSize: card, in: visible)

            switch edge {
            case .bottom: #expect(hidden.maxY <= visible.minY + 4)
            case .top: #expect(hidden.minY >= visible.maxY - 4)
            case .leading: #expect(hidden.maxX <= visible.minX + 4)
            case .trailing: #expect(hidden.minX >= visible.maxX - 4)
            case .floating: break
            }

            if edge.isVertical {
                #expect(hidden.minY == shown.minY)
            } else {
                #expect(hidden.minX == shown.minX)
            }
        }
    }

    @Test("a floating dock hides towards whichever edge it's nearest")
    func floatingHidesToNearestEdge() {
        let nearLeft = DockPlacement(edge: .floating, freePosition: CGPoint(x: 10, y: 400))
        #expect(nearLeft.hiddenFrame(contentSize: card, in: visible).maxX <= visible.minX + 4)

        let nearBottom = DockPlacement(edge: .floating, freePosition: CGPoint(x: 600, y: 4))
        #expect(nearBottom.hiddenFrame(contentSize: card, in: visible).maxY <= visible.minY + 4)
    }

    @Test("dropping a dock near an edge snaps it to that edge")
    func snapsWhenClose() {
        let dropped = CGRect(x: 500, y: visible.minY + 8, width: card.width, height: card.height)
        let placement = DockPlacement.resolving(
            droppedFrame: dropped, in: visible, orientation: .horizontal
        )
        #expect(placement.edge == .bottom)

        let landed = placement.frame(contentSize: card, in: visible)
        #expect(abs(landed.minX - dropped.minX) < 1)  // keeps where you put it along the edge
    }

    @Test("dropping one in open space leaves it floating exactly there")
    func staysFloatingWhenFarFromAnyEdge() {
        let dropped = CGRect(x: 700, y: 400, width: card.width, height: card.height)
        let placement = DockPlacement.resolving(
            droppedFrame: dropped, in: visible, orientation: .horizontal
        )
        #expect(placement.edge == .floating)
        #expect(placement.freePosition == dropped.origin)
    }

    @Test("a dock never lands outside its screen")
    func alwaysClamped() {
        let placement = DockPlacement(edge: .floating, freePosition: CGPoint(x: -900, y: 90000))
        let frame = placement.frame(contentSize: card, in: visible)
        #expect(visible.contains(frame))
    }
}

@Suite("Screens")
struct ScreenIdentityTests {

    private let laptop = ScreenIdentity(uuid: "A", name: "Built-in Retina Display", width: 1512, height: 982)
    private let studio = ScreenIdentity(uuid: "B", name: "Studio Display", width: 2560, height: 1440)

    @Test("a dock finds its own display again by uuid")
    func matchesByUUID() {
        let resolved = ScreenIdentity.resolve(wanted: studio, connected: [laptop, studio])
        #expect(resolved == studio)
    }

    @Test("a display with no uuid is still recognised by name and size")
    func matchesByNameAndSize() {
        let noUUID = ScreenIdentity(uuid: nil, name: "Studio Display", width: 2560, height: 1440)
        let resolved = ScreenIdentity.resolve(wanted: noUUID, connected: [laptop, studio])
        #expect(resolved == studio)
    }

    @Test("unplug the display and the dock has nowhere to be")
    func missingScreenResolvesToNil() {
        #expect(ScreenIdentity.resolve(wanted: studio, connected: [laptop]) == nil)
    }

    @Test("a dock pinned to nothing lands on the first screen")
    func noPreferenceUsesFirstScreen() {
        #expect(ScreenIdentity.resolve(wanted: nil, connected: [laptop, studio]) == laptop)
    }

    @Test("a uuid match beats a same-name match")
    func uuidWinsOverName() {
        let twin = ScreenIdentity(uuid: "C", name: "Studio Display", width: 2560, height: 1440)
        let resolved = ScreenIdentity.resolve(wanted: studio, connected: [twin, studio])
        #expect(resolved == studio)
    }
}
