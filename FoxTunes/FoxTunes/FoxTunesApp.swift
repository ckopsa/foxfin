import SwiftUI

@main
struct FoxTunesApp: App {
    @StateObject private var jellyfinClient = JellyfinClient()
    @StateObject private var audioEngine = AudioEngine()
    @State private var nowPlayingManager: NowPlayingManager?

    var body: some Scene {
        MenuBarExtra("FoxTunes", systemImage: "music.note") {
            ContentView()
                .environmentObject(jellyfinClient)
                .environmentObject(audioEngine)
                .onAppear {
                    if nowPlayingManager == nil {
                        nowPlayingManager = NowPlayingManager(audioEngine: audioEngine)
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
