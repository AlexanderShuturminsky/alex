import Foundation

/// How many successful races each letter has. Seven fills the row of dashes.
struct LevelProgress: Equatable, Codable {
    static let required = 7
    var passes: [String: Int] = [:]

    func count(for id: String) -> Int {
        min(Self.required, max(0, passes[id] ?? 0))
    }

    func isComplete(_ id: String) -> Bool {
        count(for: id) >= Self.required
    }

    mutating func recordPass(_ id: String) {
        let next = count(for: id) + 1
        guard next <= Self.required else { return }
        passes[id] = next
    }
}
