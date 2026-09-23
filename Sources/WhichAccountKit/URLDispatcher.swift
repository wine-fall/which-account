import Foundation

/// Hands URLs to `route` one at a time and reports once, when the queue drains.
///
/// LaunchServices delivers to the running process, so a second link can arrive while
/// the first one's picker is still open. Dropping it would lose the link with no
/// error anywhere, so it waits its turn instead.
public final class URLDispatcher {
    /// Route one URL, then call `done` — synchronously or later — with whether the
    /// hand-off to the browser succeeded. A cancelled picker counts as success:
    /// nothing was lost, the user chose not to open it.
    public typealias Route = (_ raw: String, _ done: @escaping (_ succeeded: Bool) -> Void) -> Void

    private let route: Route
    private let finish: (Int32) -> Void

    private var pending: [String] = []
    private var isRouting = false
    private var anyFailed = false
    private var generation = 0

    public private(set) var receivedAnyURL = false

    public init(route: @escaping Route, finish: @escaping (Int32) -> Void) {
        self.route = route
        self.finish = finish
    }

    public func enqueue(_ raw: String) {
        receivedAnyURL = true
        pending.append(raw)
        routeNextIfIdle()
    }

    private func routeNextIfIdle() {
        guard !isRouting else { return }
        guard !pending.isEmpty else {
            finish(anyFailed ? 1 : 0)
            return
        }

        isRouting = true
        generation += 1
        let mine = generation
        let raw = pending.removeFirst()

        route(raw) { [weak self] succeeded in
            // A route that calls `done` twice must not advance the queue twice.
            guard let self, self.isRouting, self.generation == mine else { return }
            if !succeeded { self.anyFailed = true }
            self.isRouting = false
            self.routeNextIfIdle()
        }
    }
}
