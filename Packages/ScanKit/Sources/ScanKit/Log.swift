// Logging helpers shared by the kit. One os.Logger per component; debug
// lines carry the component prefix so a unified log filter works.
import os

enum Log {
    static let subsystem = "com.obarlier.scantome"
    static let ledm = Logger(subsystem: subsystem, category: "ledm")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let discover = Logger(subsystem: subsystem, category: "discover")
    static let sink = Logger(subsystem: subsystem, category: "sink")
    static let pdf = Logger(subsystem: subsystem, category: "pdf")
    static let escl = Logger(subsystem: subsystem, category: "escl")
}
