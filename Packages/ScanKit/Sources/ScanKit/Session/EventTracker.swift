// Remembers which event-table rows were already handled.
import Foundation

/// Tracks the AgingStamp per event category so a row is handled once, and
/// decides whether a ScanEvent targets our destination.
public struct EventTracker: Sendable {
    private var seen: [String: String] = [:]

    public init() {}

    /// Records the current stamps so old events are not replayed on startup.
    public mutating func prime(with table: EventTable) {
        for e in table.events { seen[e.category] = e.agingStamp }
    }

    /// Returns the events not seen before and marks them seen.
    public mutating func unseen(in events: [Event]) -> [Event] {
        var out: [Event] = []
        for e in events where seen[e.category] != e.agingStamp {
            seen[e.category] = e.agingStamp
            out.append(e)
        }
        return out
    }

    /// True when a payload references `destinationURI`. Events that carry no
    /// destination reference at all are treated as ours.
    public static func isForMe(_ e: Event, destinationURI: String) -> Bool {
        var sawDestination = false
        for p in e.payloads where p.resourceType.contains("Destination") {
            sawDestination = true
            if p.resourceURI.hasSuffix(destinationURI) || destinationURI.hasSuffix(p.resourceURI) {
                return true
            }
        }
        return !sawDestination
    }
}
