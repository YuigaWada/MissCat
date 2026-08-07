import Foundation

indirect enum MissCatMFMNode: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case strong
        case emphasis
        case strikethrough
        case code
    }

    case text(String)
    case plain(String)
    case styled(Style, [MissCatMFMNode])
    case link(URL, [MissCatMFMNode])
    case mention(String)
    case hashtag(String)
    case customEmoji(String)
    case code(String, language: String?, isBlock: Bool)
    case quote([MissCatMFMNode])
    case center([MissCatMFMNode])
    case function(
        name: String,
        arguments: [String: String?],
        children: [MissCatMFMNode],
        literal: String
    )
    case search(String)
}

/// A bounded, side-effect-free parser for the user-facing grammar documented
/// by Misskey. Unknown or malformed input always falls back to visible text.
enum MissCatNativeMFMParser {
    private static let maximumNestingDepth = 32

    static func parse(_ source: String) -> [MissCatMFMNode] {
        Parser(source: normalizeLegacySource(source), depth: 0).parse(allowBlocks: true)
    }

    private static func normalizeLegacySource(_ source: String) -> String {
        source
            .replacingOccurrences(of: "(((", with: "")
            .replacingOccurrences(of: ")))", with: "")
    }

    private struct Parser {
        let source: String
        let depth: Int

        func parse(allowBlocks: Bool) -> [MissCatMFMNode] {
            guard depth <= maximumNestingDepth else { return [.text(source)] }
            var nodes: [MissCatMFMNode] = []
            var buffer = ""
            var cursor = source.startIndex

            func flush(_ nodes: inout [MissCatMFMNode], _ buffer: inout String) {
                guard !buffer.isEmpty else { return }
                if case let .text(previous)? = nodes.last {
                    nodes[nodes.index(before: nodes.endIndex)] = .text(previous + buffer)
                } else {
                    nodes.append(.text(buffer))
                }
                buffer.removeAll(keepingCapacity: true)
            }

            while cursor < source.endIndex {
                if let token = token(at: cursor, allowBlocks: allowBlocks) {
                    flush(&nodes, &buffer)
                    nodes.append(contentsOf: token.nodes)
                    cursor = token.end
                } else {
                    buffer.append(source[cursor])
                    cursor = source.index(after: cursor)
                }
            }
            flush(&nodes, &buffer)
            return nodes
        }

        private func token(at index: String.Index, allowBlocks: Bool) -> Token? {
            if let escaped = escapedMarker(at: index) { return escaped }
            if allowBlocks, isLineStart(index) {
                if let code = blockCode(at: index) { return code }
                if let quote = quote(at: index) { return quote }
                if let math = blockMath(at: index) { return math }
                if let search = search(at: index) { return search }
            }
            if let plain = tagged(at: index, open: "<plain>", close: "</plain>", plain: true) {
                return plain
            }
            if let center = tagged(at: index, open: "<center>", close: "</center>", center: true) {
                return center
            }
            if let bold = tagged(at: index, open: "<b>", close: "</b>", style: .strong) {
                return bold
            }
            if let italic = tagged(at: index, open: "<i>", close: "</i>", style: .emphasis) {
                return italic
            }
            if let strike = tagged(at: index, open: "<s>", close: "</s>", style: .strikethrough) {
                return strike
            }
            if let small = tagged(at: index, open: "<small>", close: "</small>") {
                return small
            }
            if let legacy = legacyMotionTag(at: index) { return legacy }
            if let function = function(at: index) { return function }
            if let big = delimited(at: index, marker: "***", style: nil) { return big }
            if let bold = delimited(at: index, marker: "**", style: .strong) { return bold }
            if let strike = delimited(at: index, marker: "~~", style: .strikethrough) { return strike }
            if let italic = wordDelimited(
                at: index,
                marker: "*",
                style: .emphasis,
                requiresLeadingBoundary: true
            ) { return italic }
            if let bold = wordDelimited(
                at: index,
                marker: "__",
                style: .strong,
                requiresLeadingBoundary: false
            ) { return bold }
            if let italic = wordDelimited(
                at: index,
                marker: "_",
                style: .emphasis,
                requiresLeadingBoundary: true
            ) { return italic }
            if let code = inlineCode(at: index) { return code }
            if let math = inlineMath(at: index) { return math }
            if let link = labelledLink(at: index) { return link }
            if let bracketedURL = bracketedURL(at: index) { return bracketedURL }
            if let url = url(at: index) { return url }
            if let mention = mention(at: index) { return mention }
            if let hashtag = hashtag(at: index) { return hashtag }
            if let emoji = customEmoji(at: index) { return emoji }
            return nil
        }

        /// MFM has no executable escape nodes. Treat a slash before a known
        /// marker as literal text so malformed or user-authored input cannot
        /// accidentally activate formatting, callbacks, or emoji loading.
        private func escapedMarker(at index: String.Index) -> Token? {
            guard source[index] == "\\" else { return nil }
            let markerStart = source.index(after: index)
            guard markerStart < source.endIndex else { return nil }
            let markers = ["***", "**", "~~", "__", "$[", "*", "_", ":", "`", "<"]
            guard let marker = markers.first(where: { hasPrefix($0, at: markerStart) }) else {
                return nil
            }
            return Token(
                nodes: [.text(marker)],
                end: source.index(markerStart, offsetBy: marker.count)
            )
        }

        private func childParser(_ text: String, allowBlocks: Bool = false) -> [MissCatMFMNode] {
            Parser(source: text, depth: depth + 1).parse(allowBlocks: allowBlocks)
        }

        private func blockCode(at index: String.Index) -> Token? {
            guard hasPrefix("```", at: index),
                  let headerEnd = source[index...].firstIndex(of: "\n") else { return nil }
            let contentStart = source.index(after: headerEnd)
            guard let close = source.range(
                of: "\n```",
                range: contentStart ..< source.endIndex
            ) else { return nil }
            let closeFenceEnd = source.index(close.lowerBound, offsetBy: 4)
            guard closeFenceEnd == source.endIndex || source[closeFenceEnd] == "\n" else { return nil }
            let languageStart = source.index(index, offsetBy: 3)
            let language = String(source[languageStart ..< headerEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let code = String(source[contentStart ..< close.lowerBound])
            let end = closeFenceEnd < source.endIndex
                ? source.index(after: closeFenceEnd)
                : closeFenceEnd
            return Token(
                nodes: [.code(code, language: language.isEmpty ? nil : language, isBlock: true)],
                end: end
            )
        }

        private func quote(at index: String.Index) -> Token? {
            guard source[index] == ">" else { return nil }
            var lineStart = index
            var contents: [String] = []
            var finalEnd = index
            while lineStart < source.endIndex, source[lineStart] == ">" {
                var contentStart = source.index(after: lineStart)
                if contentStart < source.endIndex,
                   source[contentStart] == " " || source[contentStart] == "\t" {
                    contentStart = source.index(after: contentStart)
                }
                let lineEnd = source[contentStart...].firstIndex(of: "\n") ?? source.endIndex
                contents.append(String(source[contentStart ..< lineEnd]))
                finalEnd = lineEnd
                guard lineEnd < source.endIndex else { break }
                let next = source.index(after: lineEnd)
                guard next < source.endIndex, source[next] == ">" else { break }
                lineStart = next
            }
            guard contents.contains(where: { !$0.isEmpty }) else { return nil }
            var children: [MissCatMFMNode] = []
            for (offset, content) in contents.enumerated() {
                if offset > 0 { children.append(.text("\n▎ ")) }
                children.append(contentsOf: childParser(content))
            }
            return Token(nodes: [.quote(children)], end: finalEnd)
        }

        private func blockMath(at index: String.Index) -> Token? {
            guard hasPrefix("\\[", at: index),
                  let close = source.range(of: "\\]", range: source.index(index, offsetBy: 2) ..< source.endIndex)
            else { return nil }
            let contentStart = source.index(index, offsetBy: 2)
            let formula = String(source[contentStart ..< close.lowerBound])
                .trimmingCharacters(in: .newlines)
            return Token(
                nodes: [.code(formula, language: "math", isBlock: true)],
                end: close.upperBound
            )
        }

        private func search(at index: String.Index) -> Token? {
            let lineEnd = source[index...].firstIndex(of: "\n") ?? source.endIndex
            let line = String(source[index ..< lineEnd])
            let patterns = [#"^(.+?)[\t \u3000]+(?:\[(?:search|検索)\]|search|検索)$"#]
            for pattern in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = expression.firstMatch(
                        in: line,
                        range: NSRange(line.startIndex..., in: line)
                      ),
                      let queryRange = Range(match.range(at: 1), in: line) else { continue }
                return Token(nodes: [.search(String(line[queryRange]))], end: lineEnd)
            }
            return nil
        }

        private func tagged(
            at index: String.Index,
            open: String,
            close: String,
            plain: Bool = false,
            center: Bool = false,
            style: MissCatMFMNode.Style? = nil
        ) -> Token? {
            guard hasPrefix(open, at: index) else { return nil }
            let contentStart = source.index(index, offsetBy: open.count)
            guard let closing = source.range(
                of: close,
                range: contentStart ..< source.endIndex
            ) else { return nil }
            var content = String(source[contentStart ..< closing.lowerBound])
            if center {
                if content.first == "\n" { content.removeFirst() }
                if content.last == "\n" { content.removeLast() }
            }
            let nodes: [MissCatMFMNode]
            if plain {
                nodes = [.plain(content.trimmingSingleBoundaryNewlines())]
            } else {
                let children = childParser(content, allowBlocks: center)
                if center {
                    nodes = [.center(children)]
                } else if let style {
                    nodes = [.styled(style, children)]
                } else {
                    nodes = children
                }
            }
            return Token(nodes: nodes, end: closing.upperBound)
        }

        private func legacyMotionTag(at index: String.Index) -> Token? {
            guard source[index] == "<" else { return nil }
            let remainder = String(source[index...])
            guard let openExpression = try? NSRegularExpression(
                pattern: #"^<(motion|flip|spin|jump)(?:\s+[^>]*)?>"#,
                options: .caseInsensitive
            ),
            let match = openExpression.firstMatch(
                in: remainder,
                range: NSRange(remainder.startIndex..., in: remainder)
            ),
            let openRange = Range(match.range(at: 0), in: remainder),
            let nameRange = Range(match.range(at: 1), in: remainder)
            else { return nil }
            let name = remainder[nameRange].lowercased()
            let contentStart = source.index(index, offsetBy: remainder[openRange].count)
            let close = "</\(name)>"
            guard let closing = source.range(
                of: close,
                options: .caseInsensitive,
                range: contentStart ..< source.endIndex
            ) else { return nil }
            return Token(
                nodes: childParser(String(source[contentStart ..< closing.lowerBound])),
                end: closing.upperBound
            )
        }

        private func function(at index: String.Index) -> Token? {
            guard hasPrefix("$[", at: index), depth < maximumNestingDepth else { return nil }
            let bodyStart = source.index(index, offsetBy: 2)
            guard let close = balancedFunctionClose(from: bodyStart) else { return nil }
            let body = String(source[bodyStart ..< close])
            guard let separator = body.firstIndex(of: " ") else { return nil }
            let signature = String(body[..<separator])
            let content = String(body[body.index(after: separator)...])
            guard let parsedSignature = parseSignature(signature) else { return nil }
            let end = source.index(after: close)
            return Token(
                nodes: [.function(
                    name: parsedSignature.name,
                    arguments: parsedSignature.arguments,
                    children: childParser(content),
                    literal: String(source[index ..< end])
                )],
                end: end
            )
        }

        private func balancedFunctionClose(from start: String.Index) -> String.Index? {
            var nesting = 1
            var cursor = start
            while cursor < source.endIndex {
                if hasPrefix("$[", at: cursor) {
                    nesting += 1
                    guard nesting <= maximumNestingDepth else { return nil }
                    cursor = source.index(cursor, offsetBy: 2)
                    continue
                }
                if source[cursor] == "]" {
                    nesting -= 1
                    if nesting == 0 { return cursor }
                }
                cursor = source.index(after: cursor)
            }
            return nil
        }

        private func parseSignature(_ signature: String) -> (name: String, arguments: [String: String?])? {
            let pieces = signature.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            guard let namePiece = pieces.first,
                  namePiece.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
            else { return nil }
            var arguments: [String: String?] = [:]
            if pieces.count == 2 {
                for argument in pieces[1].split(separator: ",", omittingEmptySubsequences: false) {
                    let pair = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard let key = pair.first,
                          key.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil,
                          pair.count == 1 || pair[1].range(
                            of: #"^[A-Za-z0-9_.-]+$"#,
                            options: .regularExpression
                          ) != nil else { return nil }
                    if pair.count == 2 {
                        arguments[String(key)] = String(pair[1])
                    } else {
                        arguments.updateValue(nil, forKey: String(key))
                    }
                }
            }
            return (String(namePiece).lowercased(), arguments)
        }

        private func delimited(
            at index: String.Index,
            marker: String,
            style: MissCatMFMNode.Style?
        ) -> Token? {
            guard hasPrefix(marker, at: index) else { return nil }
            let contentStart = source.index(index, offsetBy: marker.count)
            guard let close = source.range(
                of: marker,
                range: contentStart ..< source.endIndex
            ), close.lowerBound > contentStart else { return nil }
            let content = String(source[contentStart ..< close.lowerBound])
            guard !content.contains("\n") else { return nil }
            let children = childParser(content)
            return Token(
                nodes: style.map { [.styled($0, children)] } ?? children,
                end: close.upperBound
            )
        }

        /// Mirrors the constrained `italicAsta`, `italicUnder`, and
        /// `boldUnder` parsers in the official mfm.js grammar.
        private func wordDelimited(
            at index: String.Index,
            marker: String,
            style: MissCatMFMNode.Style,
            requiresLeadingBoundary: Bool
        ) -> Token? {
            guard hasPrefix(marker, at: index) else { return nil }
            if requiresLeadingBoundary, index > source.startIndex {
                let previous = source[source.index(before: index)]
                guard !(previous.isASCII && (previous.isLetter || previous.isNumber)) else {
                    return nil
                }
            }
            let contentStart = source.index(index, offsetBy: marker.count)
            guard let close = source.range(
                of: marker,
                range: contentStart ..< source.endIndex
            ), close.lowerBound > contentStart else { return nil }
            let content = String(source[contentStart ..< close.lowerBound])
            guard content.allSatisfy({ character in
                character.isASCII && (character.isLetter || character.isNumber)
                    || character == " " || character == "\t"
            }) else { return nil }
            return Token(
                nodes: [.styled(style, [.text(content)])],
                end: close.upperBound
            )
        }

        private func inlineCode(at index: String.Index) -> Token? {
            guard source[index] == "`" else { return nil }
            let contentStart = source.index(after: index)
            guard let close = source[contentStart...].firstIndex(of: "`"), close > contentStart else { return nil }
            let code = String(source[contentStart ..< close])
            guard !code.contains("\n") else { return nil }
            return Token(
                nodes: [.code(code, language: nil, isBlock: false)],
                end: source.index(after: close)
            )
        }

        private func inlineMath(at index: String.Index) -> Token? {
            guard hasPrefix("\\(", at: index) else { return nil }
            let contentStart = source.index(index, offsetBy: 2)
            guard let close = source.range(of: "\\)", range: contentStart ..< source.endIndex) else { return nil }
            let formula = String(source[contentStart ..< close.lowerBound])
            guard !formula.contains("\n") else { return nil }
            return Token(nodes: [.code(formula, language: "math", isBlock: false)], end: close.upperBound)
        }

        private func labelledLink(at index: String.Index) -> Token? {
            let silent = hasPrefix("?[", at: index)
            guard silent || source[index] == "[" else { return nil }
            let labelStart = source.index(index, offsetBy: silent ? 2 : 1)
            guard let labelEnd = source[labelStart...].firstIndex(of: "]"),
                  source.index(after: labelEnd) < source.endIndex,
                  source[source.index(after: labelEnd)] == "(" else { return nil }
            let urlStart = source.index(labelEnd, offsetBy: 2)
            guard let urlEnd = source[urlStart...].firstIndex(of: ")"),
                  let url = URL(string: String(source[urlStart ..< urlEnd])),
                  isHTTP(url) else { return nil }
            let label = String(source[labelStart ..< labelEnd])
            guard !label.isEmpty, !label.contains("\n") else { return nil }
            return Token(
                nodes: [.link(url, childParser(label))],
                end: source.index(after: urlEnd)
            )
        }

        private func bracketedURL(at index: String.Index) -> Token? {
            guard hasPrefix("<http", at: index),
                  let close = source[index...].firstIndex(of: ">") else { return nil }
            let start = source.index(after: index)
            guard let url = URL(string: String(source[start ..< close])), isHTTP(url) else { return nil }
            return Token(nodes: [.link(url, [.text(url.absoluteString)])], end: source.index(after: close))
        }

        private func url(at index: String.Index) -> Token? {
            guard hasPrefix("https://", at: index) || hasPrefix("http://", at: index) else { return nil }
            var end = index
            var parentheses = 0
            var brackets = 0
            while end < source.endIndex {
                let character = source[end]
                if character == "(" { parentheses += 1 }
                if character == "[" { brackets += 1 }
                if character == ")" {
                    if parentheses == 0 { break }
                    parentheses -= 1
                }
                if character == "]" {
                    if brackets == 0 { break }
                    brackets -= 1
                }
                if character.isWhitespace || "<>\"'".contains(character) { break }
                end = source.index(after: end)
            }
            var candidate = String(source[index ..< end])
            while candidate.last == "." || candidate.last == "," {
                candidate.removeLast()
                end = source.index(before: end)
            }
            guard let url = URL(string: candidate), isHTTP(url) else { return nil }
            return Token(nodes: [.link(url, [.text(candidate)])], end: end)
        }

        private func mention(at index: String.Index) -> Token? {
            guard source[index] == "@", hasValidInteractiveBoundary(before: index) else { return nil }
            guard let value = anchoredMatch(
                #"^@[A-Za-z0-9_.-]+(?:@[A-Za-z0-9.-]+)?"#,
                at: index
            ) else { return nil }
            var trimmed = value
            while trimmed.last == "." || trimmed.last == "-" {
                trimmed.removeLast()
            }
            let components = trimmed.dropFirst().split(separator: "@", omittingEmptySubsequences: false)
            guard components.count <= 2,
                  components.allSatisfy({ !$0.isEmpty && $0.first != "." && $0.first != "-" }) else { return nil }
            let end = source.index(index, offsetBy: trimmed.count)
            return Token(nodes: [.mention(trimmed)], end: end)
        }

        private func hashtag(at index: String.Index) -> Token? {
            guard source[index] == "#", hasValidInteractiveBoundary(before: index) else { return nil }
            var end = source.index(after: index)
            while end < source.endIndex {
                let character = source[end]
                if character.isWhitespace || ".,!?\"'#:/[]【】<>「」".contains(character) { break }
                end = source.index(after: end)
            }
            let value = String(source[source.index(after: index) ..< end])
            guard !value.isEmpty, value.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil else { return nil }
            return Token(nodes: [.hashtag(value)], end: end)
        }

        private func customEmoji(at index: String.Index) -> Token? {
            guard source[index] == ":", hasEmojiBoundary(before: index),
                  let marker = anchoredMatch(
                    #"^:[A-Za-z0-9_+\-]+(?:@[A-Za-z0-9.-]+)?:"#,
                    at: index
                  ) else { return nil }
            let end = source.index(index, offsetBy: marker.count)
            guard hasEmojiBoundary(after: end) else { return nil }
            return Token(nodes: [.customEmoji(String(marker.dropFirst().dropLast()))], end: end)
        }

        private func hasPrefix(_ prefix: String, at index: String.Index) -> Bool {
            source[index...].hasPrefix(prefix)
        }

        private func isLineStart(_ index: String.Index) -> Bool {
            index == source.startIndex || source[source.index(before: index)] == "\n"
        }

        private func hasValidInteractiveBoundary(before index: String.Index) -> Bool {
            guard index > source.startIndex else { return true }
            let previous = source[source.index(before: index)]
            return !(previous.isASCII && (previous.isLetter || previous.isNumber || previous == "_" || previous == "@"))
        }

        private func hasEmojiBoundary(before index: String.Index) -> Bool {
            guard index > source.startIndex else { return true }
            let previous = source[source.index(before: index)]
            return !(previous.isASCII && (previous.isLetter || previous.isNumber))
        }

        private func hasEmojiBoundary(after index: String.Index) -> Bool {
            guard index < source.endIndex else { return true }
            let next = source[index]
            return !(next.isASCII && (next.isLetter || next.isNumber))
        }

        private func anchoredMatch(_ pattern: String, at index: String.Index) -> String? {
            let remainder = String(source[index...])
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: remainder,
                    range: NSRange(remainder.startIndex..., in: remainder)
                  ), match.range.location == 0,
                  let range = Range(match.range, in: remainder) else { return nil }
            return String(remainder[range])
        }

        private func isHTTP(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "https" || scheme == "http"
        }
    }

    private struct Token {
        let nodes: [MissCatMFMNode]
        let end: String.Index
    }
}

enum MissCatMFMRenderSegment: Equatable, Sendable {
    case attributed(AttributedString)
    case customEmoji(name: String, link: URL?)
}

public enum MissCatNativeMFMRenderer {
    private static let staticFunctionNames: Set<String> = [
        "tada", "jelly", "twitch", "shake", "spin", "jump", "bounce",
        "flip", "x2", "x3", "x4", "font", "blur", "rainbow", "sparkle",
        "rotate", "position", "scale", "fg", "bg", "border", "clickable",
    ]

    /// Swift-native, side-effect-free rendering. Motion and callbacks are
    /// deliberately represented as static attributed text.
    public static func render(_ source: String) -> AttributedString {
        flatten(segments(source))
    }

    /// Produces display segments from the parsed MFM tree. Custom emoji are
    /// emitted only for actual custom-emoji nodes, never by rescanning raw
    /// source. This preserves emoji inside functions while keeping `<plain>`
    /// completely literal.
    static func segments(_ source: String) -> [MissCatMFMRenderSegment] {
        mergeAdjacentAttributed(renderSegments(nodes: MissCatNativeMFMParser.parse(source)))
    }

    public static func accessibilityText(_ source: String) -> String {
        segments(source).map { segment in
            switch segment {
            case let .attributed(value): String(value.characters)
            case let .customEmoji(name, _): "\(name) 絵文字"
            }
        }.joined()
    }

    public static func interactiveValue(from url: URL, kind: String) -> String? {
        guard url.scheme == "misscat-mfm", url.host == kind else { return nil }
        let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.removingPercentEncoding?.nilIfEmpty
    }

    public static func previewURLs(in source: String, limit: Int = 1) -> [URL] {
        guard limit > 0,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }

        let range = NSRange(source.startIndex..., in: source)
        var seen = Set<String>()
        return detector.matches(in: source, range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }.prefix(limit).map { $0 }
    }

    private static func flatten(_ segments: [MissCatMFMRenderSegment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            switch segment {
            case let .attributed(value):
                result.append(value)
            case let .customEmoji(name, link):
                var marker = AttributedString(":\(name):")
                marker.link = link
                result.append(marker)
            }
        }
        return result
    }

    private static func renderSegments(nodes: [MissCatMFMNode]) -> [MissCatMFMRenderSegment] {
        nodes.flatMap(renderSegments(node:))
    }

    private static func renderSegments(node: MissCatMFMNode) -> [MissCatMFMRenderSegment] {
        switch node {
        case let .text(value), let .plain(value):
            return [.attributed(AttributedString(value))]
        case let .styled(style, children):
            return renderSegments(nodes: children).map { segment in
                guard case .attributed(var value) = segment else { return segment }
                apply(intent(for: style), to: &value)
                return .attributed(value)
            }
        case let .link(url, children):
            return renderSegments(nodes: children).map { segment in
                switch segment {
                case .attributed(var value):
                    value.link = url
                    return .attributed(value)
                case let .customEmoji(name, _):
                    return .customEmoji(name: name, link: url)
                }
            }
        case let .mention(value):
            var result = AttributedString(value)
            let account = String(value.dropFirst())
            if let encoded = account.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "misscat-mfm://mention/\(encoded)") {
                result.link = url
            }
            return [.attributed(result)]
        case let .hashtag(value):
            var result = AttributedString("#\(value)")
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "misscat-mfm://hashtag/\(encoded)") {
                result.link = url
            }
            return [.attributed(result)]
        case let .customEmoji(name):
            return [.customEmoji(name: name, link: nil)]
        case let .code(value, _, _):
            var result = AttributedString(value)
            apply(.code, to: &result)
            return [.attributed(result)]
        case let .quote(children):
            return [.attributed(AttributedString("▎ "))] + renderSegments(nodes: children)
        case let .center(children):
            return renderSegments(nodes: children)
        case let .function(name, _, children, literal):
            if name == "ruby" { return [.attributed(renderRuby(children))] }
            if name == "unixtime" {
                return [.attributed(renderUnixTime(children) ?? AttributedString(literal))]
            }
            if staticFunctionNames.contains(name) { return renderSegments(nodes: children) }
            return [.attributed(AttributedString(literal))]
        case let .search(query):
            return [.attributed(AttributedString("\(query) 🔍"))]
        }
    }

    private static func renderRuby(_ children: [MissCatMFMNode]) -> AttributedString {
        let rendered = flatten(renderSegments(nodes: children))
        let text = String(rendered.characters)
        guard let split = text.lastIndex(where: { $0.isWhitespace }) else { return rendered }
        let base = String(text[..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = String(text[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !reading.isEmpty else { return rendered }
        return AttributedString("\(base)（\(reading)）")
    }

    private static func renderUnixTime(_ children: [MissCatMFMNode]) -> AttributedString? {
        let raw = String(flatten(renderSegments(nodes: children)).characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(raw), seconds.isFinite else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return AttributedString("🕒 \(formatter.string(from: Date(timeIntervalSince1970: seconds)))")
    }

    private static func mergeAdjacentAttributed(
        _ segments: [MissCatMFMRenderSegment]
    ) -> [MissCatMFMRenderSegment] {
        var result: [MissCatMFMRenderSegment] = []
        for segment in segments {
            guard case let .attributed(value) = segment else {
                result.append(segment)
                continue
            }
            guard !value.characters.isEmpty else { continue }
            if case .attributed(var previous)? = result.last {
                previous.append(value)
                result[result.index(before: result.endIndex)] = .attributed(previous)
            } else {
                result.append(.attributed(value))
            }
        }
        return result
    }

    private static func intent(for style: MissCatMFMNode.Style) -> InlinePresentationIntent {
        switch style {
        case .strong: .stronglyEmphasized
        case .emphasis: .emphasized
        case .strikethrough: .strikethrough
        case .code: .code
        }
    }

    private static func apply(_ intent: InlinePresentationIntent, to value: inout AttributedString) {
        let runs = Array(value.runs)
        for run in runs {
            value[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    func trimmingSingleBoundaryNewlines() -> String {
        var result = self
        if result.first == "\n" { result.removeFirst() }
        if result.last == "\n" { result.removeLast() }
        return result
    }
}
