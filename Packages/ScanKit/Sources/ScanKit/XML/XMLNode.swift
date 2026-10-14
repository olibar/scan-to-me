// A tiny XML DOM on top of Foundation's XMLParser. Elements are matched by
// local name only, ignoring namespaces and prefixes, which mirrors how the
// printer documents are read: the same element appears under different
// prefixes on different firmwares.
import Foundation

/// One parsed XML element with its trimmed text and child elements.
public struct XMLNode: Sendable {
    public let name: String
    public let text: String
    public let children: [XMLNode]

    /// Parses a whole document and returns its root element.
    public static func parse(_ data: Data) throws -> XMLNode {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        let builder = Builder()
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            let reason = parser.parserError?.localizedDescription ?? builder.failure ?? "no root element"
            throw LEDMError.parse("xml: \(reason)")
        }
        return root
    }

    /// Direct children with the given local name.
    public func all(_ name: String) -> [XMLNode] {
        children.filter { $0.name == name }
    }

    /// Every element in the subtree (excluding self) with the given local name.
    public func descendants(_ name: String) -> [XMLNode] {
        var out: [XMLNode] = []
        for child in children {
            if child.name == name { out.append(child) }
            out.append(contentsOf: child.descendants(name))
        }
        return out
    }

    /// Follows a slash-separated path of local names, first match per step.
    public func first(_ path: String) -> XMLNode? {
        var node = self
        for step in path.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == step }) else { return nil }
            node = next
        }
        return node
    }

    public func string(_ path: String) -> String? {
        first(path)?.text
    }

    public func int(_ path: String) -> Int? {
        guard let s = first(path)?.text else { return nil }
        return Int(s)
    }

    // MARK: - SAX builder

    private final class Builder: NSObject, XMLParserDelegate {
        private struct Frame {
            var name: String
            var text = ""
            var children: [XMLNode] = []
        }

        private var stack: [Frame] = []
        var root: XMLNode?
        var failure: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            stack.append(Frame(name: localName(elementName)))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            guard let frame = stack.popLast() else { return }
            let node = XMLNode(name: frame.name,
                               text: frame.text.trimmingCharacters(in: .whitespacesAndNewlines),
                               children: frame.children)
            if stack.isEmpty {
                root = node
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            failure = parseError.localizedDescription
        }

        /// With shouldProcessNamespaces the element name is already local, but
        /// documents without namespace declarations keep their prefix.
        private func localName(_ name: String) -> String {
            if let colon = name.lastIndex(of: ":") {
                return String(name[name.index(after: colon)...])
            }
            return name
        }
    }
}

/// Escapes text for use inside an XML element.
func xmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.utf8.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&apos;"
        default: out.append(ch)
        }
    }
    return out
}
