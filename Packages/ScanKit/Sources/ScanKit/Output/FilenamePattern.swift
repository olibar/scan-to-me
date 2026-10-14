// Renders the user's filename pattern and picks a free name.
import Foundation

public enum FilenamePattern {
    /// Replaces {date} (yyyy-MM-dd), {time} (HHmmss) and {page} (two digits).
    public static func render(_ pattern: String, date: Date, page: Int, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        let d = f.string(from: date)
        f.dateFormat = "HHmmss"
        let t = f.string(from: date)
        return pattern
            .replacingOccurrences(of: "{date}", with: d)
            .replacingOccurrences(of: "{time}", with: t)
            .replacingOccurrences(of: "{page}", with: String(format: "%02d", page))
    }

    /// Returns "base.ext", or "base-1.ext", "base-2.ext"... until `exists` says no.
    public static func unique(base: String, ext: String, exists: (String) -> Bool) -> String {
        var name = "\(base).\(ext)"
        var i = 1
        while exists(name) {
            name = "\(base)-\(i).\(ext)"
            i += 1
        }
        return name
    }

    /// Strips characters that file systems and file providers reject.
    public static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
        let cleaned = name.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
        return cleaned.isEmpty ? "scan" : cleaned
    }
}
