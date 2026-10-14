// Reads the dimensions and component count from a JPEG header, enough to
// size a PDF page without decoding the image or depending on ImageIO.
import Foundation

struct JPEGInfo: Sendable, Equatable {
    var width: Int
    var height: Int
    /// 1 = grayscale, 3 = YCbCr/RGB, 4 = CMYK.
    var components: Int

    static func parse(_ data: Data) throws -> JPEGInfo {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw LEDMError.parse("jpeg: missing SOI marker")
        }
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { throw LEDMError.parse("jpeg: expected marker at offset \(i)") }
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }          // padding
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xD9 { break }                      // EOI before any SOF
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            let isSOF = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isSOF {
                guard i + 9 < bytes.count else { throw LEDMError.parse("jpeg: truncated SOF") }
                let height = Int(bytes[i + 5]) << 8 | Int(bytes[i + 6])
                let width = Int(bytes[i + 7]) << 8 | Int(bytes[i + 8])
                let components = Int(bytes[i + 9])
                return JPEGInfo(width: width, height: height, components: components)
            }
            i += 2 + length
        }
        throw LEDMError.parse("jpeg: no SOF marker found")
    }
}
