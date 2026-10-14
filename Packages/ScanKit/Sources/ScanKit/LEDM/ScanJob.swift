// /Scan/Jobs: job description and job status.
import Foundation

/// Where the paper comes from.
public enum ScanSource: String, Sendable, Codable {
    case platen = "Platen"
    case adf = "Adf"
}

/// One scan job. Width and height are in 1/300 inch.
public struct ScanSettings: Sendable, Equatable {
    public var resolution: Int
    public var width: Int
    public var height: Int
    public var color: Bool
    /// JPEG CompressionQFactor, lower is better (15..25 typical).
    public var quality = 15
    public var source: ScanSource = .platen

    /// Paper sizes in 1/300 inch units.
    public static let a4Width = 2481
    public static let a4Height = 3507
    public static let letterWidth = 2550
    public static let letterHeight = 3300

    public init(resolution: Int, width: Int, height: Int, color: Bool, quality: Int = 15, source: ScanSource = .platen) {
        self.resolution = resolution
        self.width = width
        self.height = height
        self.color = color
        self.quality = quality
        self.source = source
    }

    func xml() -> String {
        let colorSpace = color ? "Color" : "Gray"
        let q = quality > 0 ? quality : 15
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<scan:ScanJob xmlns:scan=\"http://www.hp.com/schemas/imaging/con/cnx/scan/2008/08/19\""
            + " xmlns:dd=\"http://www.hp.com/schemas/imaging/con/dictionaries/1.0/\""
            + " xmlns:fw=\"http://www.hp.com/schemas/imaging/con/firewall/2011/01/05\">"
            + "<scan:XResolution>\(resolution)</scan:XResolution><scan:YResolution>\(resolution)</scan:YResolution>"
            + "<scan:XStart>0</scan:XStart><scan:YStart>0</scan:YStart>"
            + "<scan:Width>\(width)</scan:Width><scan:Height>\(height)</scan:Height>"
            + "<scan:Format>Jpeg</scan:Format><scan:CompressionQFactor>\(q)</scan:CompressionQFactor>"
            + "<scan:ColorSpace>\(colorSpace)</scan:ColorSpace><scan:BitDepth>8</scan:BitDepth>"
            + "<scan:InputSource>\(source.rawValue)</scan:InputSource><scan:GrayRendering>NTSC</scan:GrayRendering>"
            + "<scan:ToneMap><scan:Gamma>1000</scan:Gamma><scan:Brightness>1000</scan:Brightness>"
            + "<scan:Contrast>1000</scan:Contrast><scan:Highlite>179</scan:Highlite><scan:Shadow>25</scan:Shadow></scan:ToneMap>"
            + "<scan:ContentType>Document</scan:ContentType>"
            + "</scan:ScanJob>"
    }
}

/// Status document of a running scan job.
struct JobStatus: Sendable, Equatable {
    struct PageRef: Sendable, Equatable {
        var number: Int
        var state: String
        var binaryURL: String?
    }

    var state: String
    var pre: [PageRef]
    var post: [PageRef]

    static func parse(_ data: Data) throws -> JobStatus {
        let root = try XMLNode.parse(data)
        let job = root.first("ScanJob") ?? root
        func refs(_ name: String) -> [PageRef] {
            job.all(name).map {
                PageRef(number: $0.int("PageNumber") ?? 0,
                        state: $0.string("PageState") ?? "",
                        binaryURL: $0.string("BinaryURL"))
            }
        }
        let status = JobStatus(state: root.string("JobState") ?? "", pre: refs("PreScanPage"), post: refs("PostScanPage"))
        Log.ledm.debug("ledm: scan job state=\(status.state) pre=\(status.pre.count) post=\(status.post.count)")
        return status
    }

    var uploadCompleted: Bool {
        post.contains { $0.state.caseInsensitiveCompare("UploadCompleted") == .orderedSame }
    }
}

/// Decides when to stop polling a job. Some firmwares never leave
/// "Processing" for flatbed jobs, so one uploaded page is enough there;
/// feeder jobs run until the printer reports a terminal state.
func jobFinished(_ job: JobStatus, source: ScanSource, pages: Int) -> Bool {
    switch job.state.lowercased() {
    case "completed", "canceled", "aborted":
        return true
    default:
        return source == .platen && pages > 0 && job.uploadCompleted
    }
}
