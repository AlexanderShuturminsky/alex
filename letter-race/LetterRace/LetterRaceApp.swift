import SwiftUI

@main
struct LetterRaceApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(ProgressStore())
        }
    }
}
