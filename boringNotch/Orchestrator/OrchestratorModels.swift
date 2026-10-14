import Foundation

/// GET /api/chat. All fields optional so server omissions never break decoding.
struct ChatResponse: Decodable {
    let running: Bool?
    let screen: String?
}

/// Last `maxLines` non-blank lines of a terminal screen, trailing spaces/NBSP trimmed.
func chatTail(screen: String, maxLines: Int) -> [String] {
    let junk = CharacterSet(charactersIn: " \u{a0}\t\r")
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
        var s = Substring(line)
        while let l = s.unicodeScalars.last, junk.contains(l) { s = s.dropLast() }
        return s.isEmpty ? nil : String(s)
    }
    return Array(lines.suffix(maxLines))
}
