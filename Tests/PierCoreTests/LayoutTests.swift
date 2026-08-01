import CoreGraphics
import Foundation
import Testing

@testable import PierCore

private func apps(_ count: Int) -> [DockItem] {
    (0..<count).map { DockItem.app(at: URL(fileURLWithPath: "/Applications/App\($0).app")) }
}

@Suite("Dock layout")
struct DockLayoutTests {

    @Test("a horizontal dock is as wide as its tiles, gaps and padding")
    func horizontalCardSize() {
        let layout = DockLayout(iconSize: 48, spacing: 8, padding: 10, orientation: .horizontal)
        let size = layout.cardSize(for: apps(4))
        #expect(size.width == 236.0)
        #expect(size.height == 68.0)
    }

    @Test("a vertical dock is the same arithmetic, turned ninety degrees")
    func verticalCardSize() {
        let layout = DockLayout(iconSize: 48, spacing: 8, padding: 10, orientation: .vertical)
        let size = layout.cardSize(for: apps(4))
        #expect(size.height == 236.0)
        #expect(size.width == 68.0)
    }

    @Test("an empty dock is still a square you can drop onto")
    func emptyDockHasSize() {
        let layout = DockLayout(iconSize: 48, padding: 10)
        let size = layout.cardSize(for: [])
        #expect(size.width == 68)
        #expect(size.height == 68)
    }

    @Test("widgets take the width they ask for")
    func widgetsWidenTheDock() {
        let layout = DockLayout(iconSize: 40, spacing: 0, padding: 0, orientation: .horizontal)
        let items = [DockItem.widget(.divider), DockItem.widget(.clock)]
        // divider 0.28 + clock 1.5 = 1.78 tiles
        #expect(abs(layout.cardSize(for: items).width - 40 * 1.78) < 0.001)
    }

    @Test("tiles are laid end to end with the gap between them")
    func framesRunAlongTheAxis() {
        let layout = DockLayout(iconSize: 50, spacing: 10, padding: 5, orientation: .horizontal)
        let frames = layout.frames(for: apps(3))
        #expect(frames.map(\.minX) == [5, 65, 125])
        #expect(frames.allSatisfy { $0.minY == 5 && $0.height == 50 })
    }

    @Test("hit testing finds the tile under a point, and nothing in the padding")
    func indexAtPoint() {
        let layout = DockLayout(iconSize: 50, spacing: 10, padding: 5, orientation: .horizontal)
        let items = apps(3)
        #expect(layout.index(at: CGPoint(x: 30, y: 30), items: items) == 0)
        #expect(layout.index(at: CGPoint(x: 90, y: 30), items: items) == 1)
        #expect(layout.index(at: CGPoint(x: 60, y: 30), items: items) == nil)  // the gap
        #expect(layout.index(at: CGPoint(x: 2, y: 30), items: items) == nil)   // the padding
    }

    @Test("a drop lands where the pointer is, counting gaps not tiles")
    func insertionIndex() {
        let layout = DockLayout(iconSize: 50, spacing: 10, padding: 5, orientation: .horizontal)
        let items = apps(3)
        #expect(layout.insertionIndex(at: CGPoint(x: 0, y: 30), items: items) == 0)
        #expect(layout.insertionIndex(at: CGPoint(x: 20, y: 30), items: items) == 0)
        #expect(layout.insertionIndex(at: CGPoint(x: 45, y: 30), items: items) == 1)
        #expect(layout.insertionIndex(at: CGPoint(x: 500, y: 30), items: items) == 3)
    }

    @Test("dropping on an empty dock lands at the front")
    func insertionIntoEmptyDock() {
        let layout = DockLayout()
        #expect(layout.insertionIndex(at: CGPoint(x: 40, y: 20), items: []) == 0)
    }

    @Test("the window is the card plus room for the shadow and the swell")
    func windowLeavesRoomToGrow() {
        let layout = DockLayout(iconSize: 48, orientation: .horizontal, bleed: 30)
        let card = layout.cardSize(for: apps(2))
        let window = layout.windowSize(for: apps(2))
        #expect(window.width == card.width + 60)
        #expect(window.height == card.height + 60)
    }
}

@Suite("Magnification")
struct MagnifierTests {

    @Test("switched off, everything stays its own size")
    func offMeansFlat() {
        let magnifier = Magnifier(strength: 0)
        #expect(magnifier.scales(count: 5, hovered: 2) == [1, 1, 1, 1, 1])
        #expect(magnifier.isEnabled == false)
    }

    @Test("no pointer, no swell")
    func noHoverMeansFlat() {
        #expect(Magnifier().scales(count: 4, hovered: nil) == [1, 1, 1, 1])
    }

    @Test("the hovered tile is the biggest one")
    func peakIsUnderThePointer() {
        let scales = Magnifier(strength: 0.6, radius: 2).scales(count: 5, hovered: 2)
        #expect(scales[2] == scales.max())
        #expect(abs(scales[2] - 1.6) < 0.0001)
    }

    @Test("the swell is symmetric around the pointer")
    func swellIsSymmetric() {
        let scales = Magnifier(strength: 0.6, radius: 2).scales(count: 5, hovered: 2)
        #expect(abs(scales[1] - scales[3]) < 0.0001)
        #expect(abs(scales[0] - scales[4]) < 0.0001)
    }

    @Test("it falls to nothing at the edge of its radius, with no seam")
    func fallsOffToOne() {
        let magnifier = Magnifier(strength: 0.8, radius: 2)
        #expect(abs(magnifier.scale(distanceInItems: 2) - 1) < 0.0001)
        #expect(abs(magnifier.scale(distanceInItems: 9) - 1) < 0.0001)
    }

    @Test("tiles shrink monotonically as they get further from the pointer")
    func decreasesWithDistance() {
        let scales = Magnifier(strength: 0.7, radius: 3).scales(count: 7, hovered: 3)
        for index in 3..<6 {
            #expect(scales[index] >= scales[index + 1])
        }
    }

    @Test("hovering between two tiles lifts them equally")
    func fractionalHoverIsBalanced() {
        let scales = Magnifier(strength: 0.5, radius: 2).scales(count: 4, hovered: 1.5)
        #expect(abs(scales[1] - scales[2]) < 0.0001)
        #expect(scales[1] > scales[0])
    }

    @Test("neighbours slide apart rather than overlapping the swell")
    func neighboursMakeRoom() {
        let magnifier = Magnifier(strength: 0.6, radius: 2)
        let offsets = magnifier.offsets(count: 5, hovered: 2, itemLength: 50)
        #expect(offsets[0] < 0)      // left of the pointer moves left
        #expect(offsets[4] > 0)      // right of it moves right
        #expect(abs(offsets[0] + offsets[4]) < 0.0001)  // and the dock doesn't drift
    }

    @Test("without a pointer nothing moves")
    func noHoverNoOffsets() {
        #expect(Magnifier().offsets(count: 3, hovered: nil, itemLength: 50) == [0, 0, 0])
    }

    @Test("strength is clamped, so a bad config can't produce a dock the size of a wall")
    func strengthIsClamped() {
        #expect(Magnifier(strength: 5).maximumScale == 2)
        #expect(Magnifier(strength: -2).isEnabled == false)
    }
}
