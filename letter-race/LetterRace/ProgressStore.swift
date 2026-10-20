import Combine
import Foundation

/// Remembers how many times each letter has been raced, on this phone.
final class ProgressStore: ObservableObject {
    @Published private(set) var progress = LevelProgress()
    private let defaultsKey = "letterRace.passes"

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(LevelProgress.self, from: data) else { return }
        progress = saved
    }

    func recordPass(for id: String) {
        progress.recordPass(id)
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
