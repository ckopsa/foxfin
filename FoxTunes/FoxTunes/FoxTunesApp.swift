import SwiftUI
import JellyfinAPI
import AudioEngine

@main
struct FoxTunesApp: App {
    @StateObject private var jellyfinClient = JellyfinClient()
    @StateObject private var audioEngine = AudioEngine()
    @State private var nowPlayingManager: NowPlayingManager?
    @State private var sessionReporter: SessionReporter?

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(jellyfinClient)
                .environmentObject(audioEngine)
                .onAppear { initManagers() }
        }
        .defaultSize(width: 900, height: 600)

        MenuBarExtra("FoxTunes", systemImage: "music.note") {
            ContentView()
                .environmentObject(jellyfinClient)
                .environmentObject(audioEngine)
                .onAppear { initManagers() }
        }
        .menuBarExtraStyle(.window)
    }

    private func initManagers() {
        if nowPlayingManager == nil {
            nowPlayingManager = NowPlayingManager(audioEngine: audioEngine)
        }
        if sessionReporter == nil {
            sessionReporter = SessionReporter(
                jellyfinClient: jellyfinClient,
                audioEngine: audioEngine
            )
        }
    }
}
