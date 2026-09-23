import XCTest
@testable import WhichAccountKit

final class URLDispatcherTests: XCTestCase {

    /// A route whose completion the test controls, standing in for an open picker.
    private final class Harness {
        var routed: [String] = []
        var pendingDone: [(Bool) -> Void] = []
        var finished: [Int32] = []
        /// When set, every route completes immediately with this result.
        var completeImmediately: Bool?

        lazy var dispatcher = URLDispatcher(
            route: { [unowned self] raw, done in
                self.routed.append(raw)
                if let result = self.completeImmediately {
                    done(result)
                } else {
                    self.pendingDone.append(done)
                }
            },
            finish: { [unowned self] code in self.finished.append(code) })

        /// Finish the oldest open route. Fails the test — rather than crashing the
        /// whole test process — when nothing is waiting, which is exactly what happens
        /// if a URL was dropped instead of queued.
        func completeNext(_ result: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
            guard !pendingDone.isEmpty else {
                XCTFail("no route is waiting to complete — was a URL dropped?", file: file, line: line)
                return
            }
            pendingDone.removeFirst()(result)
        }
    }

    func testSingleURLIsRoutedThenFinishesCleanly() {
        let h = Harness()
        h.completeImmediately = true

        h.dispatcher.enqueue("https://a.example")

        XCTAssertEqual(h.routed, ["https://a.example"])
        XCTAssertEqual(h.finished, [0])
    }

    /// The bug this exists for: a link arriving while the first link's picker is still
    /// open used to be dropped without a trace.
    func testURLArrivingWhileAPickerIsOpenIsNotDropped() {
        let h = Harness()

        h.dispatcher.enqueue("https://first.example")     // picker opens
        h.dispatcher.enqueue("https://second.example")    // arrives meanwhile

        XCTAssertEqual(h.routed, ["https://first.example"], "must wait for the open picker")
        XCTAssertTrue(h.finished.isEmpty, "must not exit with a URL still queued")

        h.completeNext()
        XCTAssertEqual(h.routed, ["https://first.example", "https://second.example"])
        XCTAssertTrue(h.finished.isEmpty)

        h.completeNext()
        XCTAssertEqual(h.finished, [0])
    }

    func testOrderIsPreserved() {
        let h = Harness()
        for n in 1...4 { h.dispatcher.enqueue("https://\(n).example") }
        for _ in 1...4 { h.completeNext() }

        XCTAssertEqual(h.routed, (1...4).map { "https://\($0).example" })
        XCTAssertEqual(h.finished, [0])
    }

    /// Several URLs in one `application(_:open:)` call, all handled synchronously.
    func testBatchOfImmediateURLsIsAllRoutedAndFinishesOnce() {
        let h = Harness()
        h.completeImmediately = true

        // The first completes synchronously and finishes before the second is queued;
        // each later URL restarts the queue. Every one must still be routed.
        for n in 1...3 { h.dispatcher.enqueue("https://\(n).example") }

        XCTAssertEqual(h.routed.count, 3)
        XCTAssertEqual(h.finished.last, 0)
    }

    func testAnyFailedHandOffMakesTheExitNonZero() {
        let h = Harness()
        h.dispatcher.enqueue("https://fails.example")
        h.dispatcher.enqueue("https://works.example")

        h.completeNext(false)
        h.completeNext(true)

        XCTAssertEqual(h.finished, [1], "a lost URL must not be reported as success")
    }

    func testCompletingTwiceDoesNotSkipAQueuedURL() {
        let h = Harness()
        h.dispatcher.enqueue("https://a.example")
        h.dispatcher.enqueue("https://b.example")
        h.dispatcher.enqueue("https://c.example")

        guard !h.pendingDone.isEmpty else { return XCTFail("a.example was never routed") }
        let doneA = h.pendingDone.removeFirst()
        doneA(true)
        doneA(true)   // a buggy route calls back twice

        XCTAssertEqual(h.routed, ["https://a.example", "https://b.example"],
                       "the second callback must not advance past b")
    }

    func testReceivedAnyURLTracksDelivery() {
        let h = Harness()
        XCTAssertFalse(h.dispatcher.receivedAnyURL)
        h.dispatcher.enqueue("https://a.example")
        XCTAssertTrue(h.dispatcher.receivedAnyURL)
    }
}
