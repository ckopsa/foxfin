import SwiftUI

@main
struct FoxTunesApp: App {
    @StateObject private var jellyfinClient = JellyfinClient()
    @StateObject private var audioEngine = AudioEngine()

    var body: some Scene {
        MenuBarExtra("FoxTunes", systemImage: "music.note") {
            ContentView()
                .environmentObject(jellyfinClient)
                .environmentObject(audioEngine)
        }
        .menuBarExtraStyle(.window)
    }
}
