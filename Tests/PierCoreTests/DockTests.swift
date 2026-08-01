import CoreGraphics
import Foundation
import Testing

@testable import PierCore

private func app(_ name: String, bundle: String? = nil) -> DockItem {
    .app(at: URL(fileURLWithPath: "/Applications/\(name).app"), bundleIdentifier: bundle)
}

private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pier-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Dock contents")
struct DockContentsTests {

    @Test("items keep the order you put them in")
    func addsInOrder() {
        var dock = Dock()
        dock.add(app("Safari"))
        dock.add(app("Mail"))
        #expect(dock.items.map(\.title) == ["Safari", "Mail"])
    }

    @Test("adding at an index inserts rather than appends")
    func addsAtIndex() {
        var dock = Dock()
        dock.add(app("Safari"))
        dock.add(app("Mail"))
        dock.add(app("Notes"), at: 1)
        #expect(dock.items.map(\.title) == ["Safari", "Notes", "Mail"])
    }

    @Test("the same app twice is one icon")
    func rejectsDuplicateApps() {
        var dock = Dock()
        #expect(dock.add(app("Safari", bundle: "com.apple.Safari")) == true)
        #expect(dock.add(app("Safari", bundle: "com.apple.Safari")) == false)
        #expect(dock.items.count == 1)
    }

    @Test("two apps at the same path are the same app even without a bundle id")
    func rejectsDuplicatePaths() {
        var dock = Dock()
        dock.add(app("Safari"))
        #expect(dock.add(app("Safari")) == false)
    }

    @Test("widgets can repeat — three spacers is a legitimate layout")
    func widgetsMayRepeat() {
        var dock = Dock()
        #expect(dock.add(.widget(.spacer)) == true)
        #expect(dock.add(.widget(.spacer)) == true)
        #expect(dock.add(.widget(.divider)) == true)
        #expect(dock.items.count == 3)
    }

    @Test("adding several returns only the ones that landed")
    func addContentsOfReportsWhatLanded() {
        var dock = Dock()
        dock.add(app("Safari"))
        let landed = dock.add(contentsOf: [app("Safari"), app("Mail"), app("Notes")])
        #expect(landed.map(\.title) == ["Mail", "Notes"])
    }

    @Test("dragging an icon rightwards accounts for the hole it leaves behind")
    func moveForward() {
        var dock = Dock()
        ["A", "B", "C", "D"].forEach { dock.add(app($0)) }
        dock.move(id: dock.items[0].id, to: 3)
        #expect(dock.items.map(\.title) == ["B", "C", "A", "D"])
    }

    @Test("dragging an icon leftwards puts it exactly where the gap was")
    func moveBackward() {
        var dock = Dock()
        ["A", "B", "C", "D"].forEach { dock.add(app($0)) }
        dock.move(id: dock.items[3].id, to: 1)
        #expect(dock.items.map(\.title) == ["A", "D", "B", "C"])
    }

    @Test("moving past the end is the same as moving to the end")
    func moveClamps() {
        var dock = Dock()
        ["A", "B"].forEach { dock.add(app($0)) }
        dock.move(id: dock.items[0].id, to: 99)
        #expect(dock.items.map(\.title) == ["B", "A"])
    }

    @Test("removing gives back what left, for undo and for cleanup")
    func removeReturnsItem() {
        var dock = Dock()
        dock.add(app("Safari"))
        let removed = dock.remove(id: dock.items[0].id)
        #expect(removed?.title == "Safari")
        #expect(dock.isEmpty)
    }

    @Test("only apps and folders take a dropped file")
    func dropTargets() {
        #expect(app("Safari").acceptsDrops)
        #expect(DockItem.folder(at: URL(fileURLWithPath: "/tmp")).acceptsDrops)
        #expect(DockItem.widget(.trash).acceptsDrops)
        #expect(DockItem.widget(.clock).acceptsDrops == false)
        #expect(DockItem.file(at: URL(fileURLWithPath: "/tmp/a.txt")).acceptsDrops == false)
    }

    @Test("spacers and dividers are furniture — no clicks, no drops")
    func decorativeWidgetsAreInert() {
        #expect(DockItem.widget(.spacer).isInteractive == false)
        #expect(DockItem.widget(.divider).isInteractive == false)
        #expect(DockItem.widget(.trash).isInteractive)
    }
}

@Suite("Appearance")
struct AppearanceTests {

    @Test("a hand-edited config can't make a dock the size of a wall")
    func clampsEverything() {
        var wild = DockAppearance()
        wild.iconSize = 9000
        wild.opacity = -3
        wild.magnification = 88
        wild.cornerRadius = 400

        let safe = wild.sanitised
        #expect(safe.iconSize == 128)
        #expect(safe.opacity == 0.15)
        #expect(safe.magnification == 1)
        #expect(safe.cornerRadius == 60)
    }

    @Test("the dock's bleed grows with magnification, so big icons aren't clipped")
    func bleedFollowsMagnification() {
        var dock = Dock()
        dock.appearance.iconSize = 64
        dock.appearance.magnification = 0
        let calm = dock.layout.bleed

        dock.appearance.magnification = 1
        #expect(dock.layout.bleed > calm)
    }

    @Test("older config files load with defaults for anything they don't mention")
    func partialConfigLoads() throws {
        let json = #"{"iconSize": 72}"#
        let appearance = try JSONDecoder.pier.decode(DockAppearance.self, from: Data(json.utf8))
        #expect(appearance.iconSize == 72)
        #expect(appearance.material == .hud)
        #expect(appearance.showRunningIndicators)
    }
}

@Suite("Dock store")
struct DockStoreTests {

    @Test("docks survive a relaunch, contents and all")
    func roundTrips() {
        let file = scratch().appendingPathComponent("docks.json")
        let store = DockStore(fileURL: file)

        var dock = Dock(name: "Chat")
        dock.add(app("Slack"))
        dock.add(.widget(.clock))
        dock.placement = DockPlacement(edge: .leading, alignment: .start)
        dock.appearance.iconSize = 56
        store.add(dock)

        let reopened = DockStore(fileURL: file)
        reopened.load()
        #expect(reopened.docks.count == 1)
        #expect(reopened.docks[0].name == "Chat")
        #expect(reopened.docks[0].items.count == 2)
        #expect(reopened.docks[0].placement.edge == .leading)
        #expect(reopened.docks[0].appearance.iconSize == 56)
    }

    @Test("a corrupt file means no docks, and the bad copy is kept for rescue")
    func survivesCorruption() throws {
        let file = scratch().appendingPathComponent("docks.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)

        let store = DockStore(fileURL: file)
        store.load()
        #expect(store.docks.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("broken").path))
    }

    @Test("a missing file is a first launch, not an error")
    func missingFileIsEmpty() {
        let store = DockStore(fileURL: scratch().appendingPathComponent("nothing.json"))
        store.load()
        #expect(store.docks.isEmpty)
    }

    @Test("every change is written through and announced once")
    func broadcastsChanges() {
        let store = DockStore(fileURL: scratch().appendingPathComponent("docks.json"))
        var notifications = 0
        store.onChange = { _ in notifications += 1 }

        let dock = store.add(Dock(name: "One"))
        store.update(id: dock.id) { $0.add(app("Safari")) }
        store.remove(id: dock.id)
        #expect(notifications == 3)
    }

    @Test("dragging a dock around saves without rebuilding every window")
    func quietUpdatesDontBroadcast() {
        let store = DockStore(fileURL: scratch().appendingPathComponent("docks.json"))
        let dock = store.add(Dock())
        var notifications = 0
        store.onChange = { _ in notifications += 1 }

        store.updateQuietly(id: dock.id) { $0.placement.freePosition = CGPoint(x: 10, y: 10) }
        #expect(notifications == 0)
        #expect(store.dock(id: dock.id)?.placement.freePosition == CGPoint(x: 10, y: 10))
    }

    @Test("duplicating a dock copies its look but gives everything new ids")
    func duplicateIsIndependent() {
        let store = DockStore(fileURL: scratch().appendingPathComponent("docks.json"))
        var dock = Dock(name: "Work")
        dock.add(app("Xcode"))
        store.add(dock)

        let copy = store.duplicate(id: dock.id)
        #expect(copy?.name == "Work copy")
        #expect(copy?.id != dock.id)
        #expect(copy?.items[0].id != dock.items[0].id)
        #expect(copy?.items[0].title == "Xcode")
    }
}

@Suite("Mirroring the macOS Dock")
struct SystemDockTests {

    @Test("app tiles are read out of the Dock's own nested plist")
    func parsesPersistentApps() {
        let entries: [Any] = [
            ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Safari.app/"]]],
            ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Mail.app/"]]],
        ]
        let urls = SystemDock.urls(fromPersistentEntries: entries)
        #expect(urls.map(\.lastPathComponent) == ["Safari.app", "Mail.app"])
    }

    @Test("tiles that aren't files at all are skipped rather than crashing")
    func skipsJunkEntries() {
        let entries: [Any] = [
            "nonsense",
            ["tile-data": ["something-else": 1]],
            ["no-tile-data": true],
            ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Notes.app/"]]],
        ]
        #expect(SystemDock.urls(fromPersistentEntries: entries).count == 1)
    }

    @Test("a plain path works as well as a file URL")
    func acceptsBarePaths() {
        let entries: [Any] = [["tile-data": ["file-data": "/Applications/Terminal.app"]]]
        #expect(SystemDock.urls(fromPersistentEntries: entries).first?.lastPathComponent == "Terminal.app")
    }

    @Test("apps become apps, folders become folders, and deleted things are dropped")
    func buildsItems() {
        let urls = [
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/Users/me/Downloads"),
            URL(fileURLWithPath: "/Applications/Deleted.app"),
        ]
        let items = SystemDock.items(from: urls) { $0.lastPathComponent != "Deleted.app" }
        #expect(items.map(\.kind) == [.app, .folder])
    }
}
