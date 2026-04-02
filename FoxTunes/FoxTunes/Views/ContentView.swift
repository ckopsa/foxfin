import SwiftUI

struct ContentView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @EnvironmentObject var audioEngine: AudioEngine

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingView()
            Divider()
            LibraryBrowserView()
        }
        .frame(width: 320, height: 480)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var audioEngine: AudioEngine

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(audioEngine.currentTrackName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(audioEngine.currentArtistName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 20) {
                Button(action: audioEngine.previousTrack) {
                    Image(systemName: "backward.fill")
                }
                Button(action: audioEngine.togglePlayPause) {
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button(action: audioEngine.nextTrack) {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

struct LibraryBrowserView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient

    var body: some View {
        VStack {
            if jellyfinClient.isAuthenticated {
                Text("Library")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                Text("Connect to browse your music library.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ConnectionView()
            }
            Spacer()
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject var jellyfinClient: JellyfinClient
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 8) {
            TextField("Server URL", text: $serverURL)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            Button("Connect") {
                Task {
                    await jellyfinClient.authenticate(
                        serverURL: serverURL,
                        username: username,
                        password: password
                    )
                }
            }
            .disabled(serverURL.isEmpty || username.isEmpty)
        }
        .padding()
    }
}
