// User settings that shape every scan.
import Foundation

public enum OutputFormat: String, Codable, Sendable, CaseIterable {
    case pdf
    case jpeg

    public var fileExtension: String { self == .pdf ? "pdf" : "jpg" }
}

public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case color
    case gray
}

public enum Paper: String, Codable, Sendable, CaseIterable {
    case a4
    case letter
}

/// Flat settings, mirroring the desktop client's config keys.
public struct ScanPreferences: Codable, Sendable, Equatable {
    /// Name shown in the printer's Scan to Computer menu.
    public var destinationName: String
    public var format: OutputFormat
    /// 75...1200 DPI.
    public var resolution: Int
    public var colorMode: ColorMode
    public var paper: Paper
    /// Tokens: {date} {time} {page}; {page} is used for JPEG pages only.
    public var filenamePattern: String
    /// Seconds without a new page before a multi-page PDF is closed.
    public var pageTimeout: TimeInterval
    /// Also add JPEG scans to the Photos library.
    public var saveJPEGToPhotos: Bool
    /// Cut the empty margins around originals smaller than the paper size
    /// (flatbed only; feeder pages are full pages).
    public var trimMargins: Bool

    public static let resolutionRange = 75...1200
    public static let resolutionChoices = [75, 100, 150, 200, 300, 600, 1200]

    public init(destinationName: String, format: OutputFormat = .pdf, resolution: Int = 300,
                colorMode: ColorMode = .color, paper: Paper = .a4, filenamePattern: String = "scan_{date}_{time}",
                pageTimeout: TimeInterval = 120, saveJPEGToPhotos: Bool = false, trimMargins: Bool = true) {
        self.destinationName = destinationName
        self.format = format
        self.resolution = resolution
        self.colorMode = colorMode
        self.paper = paper
        self.filenamePattern = filenamePattern
        self.pageTimeout = pageTimeout
        self.saveJPEGToPhotos = saveJPEGToPhotos
        self.trimMargins = trimMargins
    }

    /// Settings saved by older versions lack the newer keys; those take their
    /// defaults instead of failing the whole saved state.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(destinationName: try c.decode(String.self, forKey: .destinationName),
                  format: try c.decode(OutputFormat.self, forKey: .format),
                  resolution: try c.decode(Int.self, forKey: .resolution),
                  colorMode: try c.decode(ColorMode.self, forKey: .colorMode),
                  paper: try c.decode(Paper.self, forKey: .paper),
                  filenamePattern: try c.decode(String.self, forKey: .filenamePattern),
                  pageTimeout: try c.decode(TimeInterval.self, forKey: .pageTimeout),
                  saveJPEGToPhotos: try c.decodeIfPresent(Bool.self, forKey: .saveJPEGToPhotos) ?? false,
                  trimMargins: try c.decodeIfPresent(Bool.self, forKey: .trimMargins) ?? true)
    }

    public static func defaults(deviceName: String) -> ScanPreferences {
        ScanPreferences(destinationName: deviceName.isEmpty ? "Scan to Me" : deviceName)
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case emptyName, emptyPattern, resolutionOutOfRange(Int), pageTimeoutTooShort

        public var description: String {
            switch self {
            case .emptyName: return "destination name must not be empty"
            case .emptyPattern: return "filename pattern must not be empty"
            case let .resolutionOutOfRange(r): return "resolution must be between 75 and 1200, got \(r)"
            case .pageTimeoutTooShort: return "page timeout must be at least 10 seconds"
            }
        }
    }

    public func validate() throws {
        if destinationName.trimmingCharacters(in: .whitespaces).isEmpty { throw ValidationError.emptyName }
        if filenamePattern.trimmingCharacters(in: .whitespaces).isEmpty { throw ValidationError.emptyPattern }
        if !ScanPreferences.resolutionRange.contains(resolution) { throw ValidationError.resolutionOutOfRange(resolution) }
        if pageTimeout < 10 { throw ValidationError.pageTimeoutTooShort }
    }

    /// Scan job settings for a source, clamped to what the scanner reports.
    public func scanSettings(for source: ScanSource, caps: ScanCaps?) -> ScanSettings {
        var s = ScanSettings(resolution: resolution, width: ScanSettings.a4Width, height: ScanSettings.a4Height,
                             color: colorMode == .color, source: source)
        if paper == .letter {
            s.width = ScanSettings.letterWidth
            s.height = ScanSettings.letterHeight
        }
        let limits: SourceCaps? = source == .adf ? caps?.adf : caps?.platen
        if let limits {
            if limits.maxWidth > 0, s.width > limits.maxWidth { s.width = limits.maxWidth }
            if limits.maxHeight > 0, s.height > limits.maxHeight { s.height = limits.maxHeight }
            let maxRes = limits.effectiveMaxResolution
            if maxRes > 0, s.resolution > maxRes { s.resolution = maxRes }
        }
        Log.session.debug("session: scan settings source=\(source.rawValue) size=\(s.width)x\(s.height) resolution=\(s.resolution)")
        return s
    }

    /// The shortcut picked on the printer wins over the default format.
    public func format(forShortcut shortcut: String) -> OutputFormat {
        let s = shortcut.lowercased()
        if s.contains("pdf") || s.contains("document") { return .pdf }
        if s.contains("jpeg") || s.contains("jpg") || s.contains("photo") { return .jpeg }
        return format
    }
}
