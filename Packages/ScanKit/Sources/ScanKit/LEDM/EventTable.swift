// /EventMgmt/EventTable rows.
import Foundation

/// A resource reference attached to an event.
public struct Payload: Sendable, Equatable {
    public var resourceURI: String
    public var resourceType: String

    public init(resourceURI: String, resourceType: String) {
        self.resourceURI = resourceURI
        self.resourceType = resourceType
    }
}

/// One row of the printer's event table.
public struct Event: Sendable, Equatable {
    public var category: String
    public var agingStamp: String
    public var payloads: [Payload]

    public init(category: String, agingStamp: String, payloads: [Payload] = []) {
        self.category = category
        self.agingStamp = agingStamp
        self.payloads = payloads
    }
}

/// The last poll result; the ETag drives the next long-poll.
public struct EventTable: Sendable, Equatable {
    public var etag: String?
    public var events: [Event]

    public init(etag: String? = nil, events: [Event] = []) {
        self.etag = etag
        self.events = events
    }

    public static func parse(_ data: Data, etag: String?) throws -> EventTable {
        let root = try XMLNode.parse(data)
        var table = EventTable(etag: etag)
        for e in root.descendants("Event") {
            var ev = Event(category: e.string("UnqualifiedEventCategory") ?? "",
                           agingStamp: e.string("AgingStamp") ?? "")
            for p in e.all("Payload") {
                ev.payloads.append(Payload(resourceURI: p.string("ResourceURI") ?? "",
                                           resourceType: p.string("ResourceType") ?? ""))
            }
            table.events.append(ev)
        }
        Log.ledm.debug("ledm: event table events=\(table.events.count) etag=\(etag ?? "-")")
        return table
    }
}
