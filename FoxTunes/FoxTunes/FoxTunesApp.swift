import SwiftUI
import JellyfinAPI
import AudioEngine

@main
struct FoxTunesApp: App {
    @State private var jellyfinClient = JellyfinClient()
    @State private var audioEngine = AudioEngine()
    @State private var nowPlayingManager: NowPlayingManager?
    @State private var sessionReporter: SessionReporter?

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(jellyfinClient)
                .environment(audioEngine)
                .onAppear { initManagers() }
        }
        .defaultSize(width: 900, height: 600)

        MenuBarExtra("FoxTunes", systemImage: "music.note") {
            ContentView()
                .environment(jellyfinClient)
                .environment(audioEngine)
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
