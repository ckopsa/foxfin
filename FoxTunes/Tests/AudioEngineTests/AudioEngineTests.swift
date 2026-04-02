import XCTest
@testable import AudioEngine

final class AudioEngineTests: XCTestCase {
    func testQueueRepeatModeCycle() {
        let queue = PlaybackQueue()
        XCTAssertEqual(queue.repeatMode, .off)
        queue.cycleRepeat()
        XCTAssertEqual(queue.repeatMode, .all)
        queue.cycleRepeat()
        XCTAssertEqual(queue.repeatMode, .one)
        queue.cycleRepeat()
        XCTAssertEqual(queue.repeatMode, .off)
    }

    func testShuffleToggle() {
        let queue = PlaybackQueue()
        XCTAssertFalse(queue.shuffleEnabled)
        queue.toggleShuffle()
        XCTAssertTrue(queue.shuffleEnabled)
        queue.toggleShuffle()
        XCTAssertFalse(queue.shuffleEnabled)
    }
}
