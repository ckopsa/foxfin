import XCTest
@testable import AudioEngine

final class PlaybackQueueTests: XCTestCase {

    private func makeTrack(id: String = "t1", name: String = "Track") -> Track {
        Track(
            id: id, name: name, artist: "Artist", album: "Album",
            streamURL: URL(string: "http://localhost/audio/\(id)")!,
            durationSeconds: 180, mediaSourceId: id
        )
    }

    // MARK: - Basic Queue Operations

    func testSetTracksAndCurrentTrack() {
        let queue = PlaybackQueue()
        let tracks = (1...5).map { makeTrack(id: "t\($0)", name: "Track \($0)") }
        queue.setTracks(tracks, startAt: 2)
        XCTAssertEqual(queue.currentTrack?.id, "t3")
        XCTAssertEqual(queue.count, 5)
    }

    func testAdvanceThroughQueue() {
        let queue = PlaybackQueue()
        let tracks = (1...3).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 0)
        XCTAssertEqual(queue.currentTrack?.id, "t1")

        queue.advance()
        XCTAssertEqual(queue.currentTrack?.id, "t2")

        queue.advance()
        XCTAssertEqual(queue.currentTrack?.id, "t3")

        // Past end with repeat off
        queue.advance()
        XCTAssertNil(queue.currentTrack)
    }

    func testGoBack() {
        let queue = PlaybackQueue()
        let tracks = (1...3).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 2)
        queue.goBack()
        XCTAssertEqual(queue.currentTrack?.id, "t2")
        queue.goBack()
        XCTAssertEqual(queue.currentTrack?.id, "t1")
        queue.goBack() // Can't go before 0
        XCTAssertEqual(queue.currentTrack?.id, "t1")
    }

    func testPeekNext() {
        let queue = PlaybackQueue()
        let tracks = (1...3).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 0)
        XCTAssertEqual(queue.peekNext?.id, "t2")
        XCTAssertEqual(queue.currentTrack?.id, "t1") // Didn't advance
    }

    // MARK: - Append / Remove / Move

    func testAppend() {
        let queue = PlaybackQueue()
        queue.setTracks([makeTrack(id: "t1")])
        queue.append(makeTrack(id: "t2"))
        XCTAssertEqual(queue.count, 2)
    }

    func testRemoveBeforeCurrent() {
        let queue = PlaybackQueue()
        let tracks = (1...4).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 2)
        queue.remove(at: 0)
        // currentIndex adjusted: was 2, item before removed, now 1
        XCTAssertEqual(queue.currentTrack?.id, "t3")
        XCTAssertEqual(queue.count, 3)
    }

    func testMoveTrack() {
        let queue = PlaybackQueue()
        let tracks = (1...4).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 1) // Playing t2
        queue.move(from: 3, to: 0)
        // t4 moved before t1; t2 is now at index 2
        XCTAssertEqual(queue.currentTrack?.id, "t2")
    }

    func testClear() {
        let queue = PlaybackQueue()
        queue.setTracks((1...3).map { makeTrack(id: "t\($0)") })
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.currentTrack)
    }

    // MARK: - Repeat Modes

    func testRepeatAll() {
        let queue = PlaybackQueue()
        let tracks = (1...2).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 0)
        queue.cycleRepeat() // .off -> .all
        XCTAssertEqual(queue.repeatMode, .all)

        queue.advance() // t2
        queue.advance() // wraps to t1
        XCTAssertEqual(queue.currentTrack?.id, "t1")
    }

    func testRepeatOne() {
        let queue = PlaybackQueue()
        let tracks = (1...2).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 0)
        queue.cycleRepeat() // .all
        queue.cycleRepeat() // .one
        XCTAssertEqual(queue.repeatMode, .one)

        queue.advance() // stays on t1
        XCTAssertEqual(queue.currentTrack?.id, "t1")
    }

    func testRepeatModeCycle() {
        let queue = PlaybackQueue()
        XCTAssertEqual(queue.repeatMode, .off)
        queue.cycleRepeat()
        XCTAssertEqual(queue.repeatMode, .all)
        queue.cycleRepeat()
        XCTAssertEqual(queue.repeatMode, .one)
        queue.cycleRepeat()
        XCTAssertEqual(queue.repeatMode, .off)
    }

    // MARK: - Shuffle

    func testShuffleToggle() {
        let queue = PlaybackQueue()
        XCTAssertFalse(queue.shuffleEnabled)
        queue.toggleShuffle()
        XCTAssertTrue(queue.shuffleEnabled)
        queue.toggleShuffle()
        XCTAssertFalse(queue.shuffleEnabled)
    }

    func testShufflePreservesCurrentTrack() {
        let queue = PlaybackQueue()
        let tracks = (1...10).map { makeTrack(id: "t\($0)") }
        queue.setTracks(tracks, startAt: 3)
        let current = queue.currentTrack
        queue.toggleShuffle()
        XCTAssertEqual(queue.currentTrack?.id, current?.id)
    }

    // MARK: - Edge Cases

    func testEmptyQueue() {
        let queue = PlaybackQueue()
        XCTAssertNil(queue.currentTrack)
        XCTAssertNil(queue.peekNext)
        XCTAssertTrue(queue.isEmpty)
        queue.advance() // No crash
        queue.goBack()  // No crash
    }
}

final class AudioEngineStateTests: XCTestCase {
    func testInitialState() {
        let engine = AudioEngine()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.currentTrackName, "Not Playing")
        XCTAssertEqual(engine.currentArtistName, "")
        XCTAssertEqual(engine.volume, 1.0)
    }

    func testVolumeClamps() {
        let engine = AudioEngine()
        engine.volume = 0.5
        XCTAssertEqual(engine.volume, 0.5)
        engine.volume = 0.0
        XCTAssertEqual(engine.volume, 0.0)
    }
}
