import CoreGraphics
import Foundation

public enum PierPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Pier", isDirectory: true)
    }

    public static var docksFile: URL {
        supportDirectory.appendingPathComponent("docks.json")
    }

    public static var iconsDirectory: URL {
        supportDirectory.appendingPathComponent("icons", isDirectory: true)
    }
}

/// Every dock, and the file they live in.
public final class DockStore {
    public private(set) var docks: [Dock] = []
    public var onChange: ((DockStore) -> Void)?

    private let fileURL: URL

    public init(fileURL: URL = PierPaths.docksFile) {
        self.fileURL = fileURL
    }

    private struct Persisted: Codable {
        var version: Int
        var docks: [Dock]
    }

    /// An unreadable file means "no docks yet", not a crash on launch. The old file is
    /// kept alongside so a bad edit is recoverable rather than silently erased.
    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            docks = []
            return
        }
        guard let decoded = try? JSONDecoder.pier.decode(Persisted.self, from: data) else {
            try? data.write(to: fileURL.appendingPathExtension("broken"), options: .atomic)
            docks = []
            return
        }
        docks = decoded.docks
    }

    public func save() {
        let payload = Persisted(version: 1, docks: docks)
        guard let data = try? JSONEncoder.pier.encode(payload) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Access

    public func dock(id: UUID) -> Dock? {
        docks.first { $0.id == id }
    }

    @discardableResult
    public func add(_ dock: Dock) -> Dock {
        docks.append(dock)
        commit()
        return dock
    }

    @discardableResult
    public func update(id: UUID, _ body: (inout Dock) -> Void) -> Dock? {
        guard let index = docks.firstIndex(where: { $0.id == id }) else { return nil }
        body(&docks[index])
        commit()
        return docks[index]
    }

    /// Saves without broadcasting — for things that change constantly, like a dock being
    /// dragged, where a full rebuild on every frame would be silly.
    public func updateQuietly(id: UUID, _ body: (inout Dock) -> Void) {
        guard let index = docks.firstIndex(where: { $0.id == id }) else { return }
        body(&docks[index])
        save()
    }

    public func remove(id: UUID) {
        docks.removeAll { $0.id == id }
        commit()
    }

    public func duplicate(id: UUID) -> Dock? {
        guard var copy = dock(id: id) else { return nil }
        copy.id = UUID()
        copy.name = "\(copy.name) copy"
        copy.items = copy.items.map { item in
            var fresh = item
            fresh.id = UUID()
            return fresh
        }
        return add(copy)
    }

    public func replaceAll(_ newDocks: [Dock]) {
        docks = newDocks
        commit()
    }

    private func commit() {
        save()
        onChange?(self)
    }
}

extension JSONEncoder {
    public static var pier: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var pier: JSONDecoder {
        JSONDecoder()
    }
}
