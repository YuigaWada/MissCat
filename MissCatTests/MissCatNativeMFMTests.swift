import Foundation
import ImageIO
@testable import MissCat
import XCTest

final class MissCatNativeMFMTests: XCTestCase {
    func testOfficialBlockSyntaxRendersWithoutMarkupArtifacts() {
        XCTAssertEqual(
            text("<center>centered **bold**</center>"),
            "centered bold"
        )
        XCTAssertEqual(
            text("> quoted\n> continued"),
            "▎ quoted\n▎ continued"
        )
        XCTAssertEqual(
            text("```swift\nlet value = 1\n```"),
            "let value = 1"
        )
    }

    func testOfficialFunctionSyntaxUsesSafeStaticRepresentations() {
        let cases: [(String, String)] = [
            ("$[ruby Misskey ミスキー]", "Misskey（ミスキー）"),
            ("$[unixtime 1701356400]", "🕒 2023-11-30 15:00:00 UTC"),
            ("$[spin.speed=5s :misskey:]", ":misskey:"),
            ("$[flip.v mirrored]", "mirrored"),
            ("$[font.monospace mono]", "mono"),
            ("$[fg.color=f00 red]", "red"),
            ("$[border.width=2 box]", "box"),
            ("$[x2 large]", "large"),
            ("$[sparkle safe]", "safe"),
        ]

        for (source, expected) in cases {
            XCTAssertEqual(text(source), expected, source)
        }
    }

    func testDocumentedOfficialSyntaxCompatibilityMatrix() {
        let cases: [(syntax: String, source: String, expected: String)] = [
            ("mention", "@repo@p1.a9z.dev", "@repo@p1.a9z.dev"),
            ("hashtag", "#Misskey", "#Misskey"),
            ("URL", "https://example.test/path", "https://example.test/path"),
            ("bracketed URL", "<https://example.test/path>", "https://example.test/path"),
            ("labelled link", "[site](https://example.test/path)", "site"),
            ("silent labelled link", "?[site](https://example.test/path)", "site"),
            ("custom emoji", ":misskey:", ":misskey:"),
            ("remote custom emoji", ":wave@remote.example:", ":wave@remote.example:"),
            ("bold asterisk", "**bold**", "bold"),
            ("bold tag", "<b>bold</b>", "bold"),
            ("bold underscore", "__bold__", "bold"),
            ("italic asterisk", "*italic*", "italic"),
            ("italic tag", "<i>italic</i>", "italic"),
            ("italic underscore", "_italic_", "italic"),
            ("strike", "~~strike~~", "strike"),
            ("strike tag", "<s>strike</s>", "strike"),
            ("large legacy form", "***large***", "large"),
            ("small", "<small>small</small>", "small"),
            ("center", "<center>center</center>", "center"),
            ("quote", "> quote", "▎ quote"),
            ("ruby", "$[ruby Misskey ミスキー]", "Misskey（ミスキー）"),
            ("unixtime", "$[unixtime 1701356400]", "🕒 2023-11-30 15:00:00 UTC"),
            ("inline code", "`let value = 1`", "let value = 1"),
            ("block code", "```swift\nlet value = 1\n```", "let value = 1"),
            ("inline math", #"\(x + y\)"#, "x + y"),
            ("block math", "\\[\nx + y\n\\]", "x + y"),
            ("search", "misskey search", "misskey 🔍"),
            ("tada", "$[tada static]", "static"),
            ("jelly", "$[jelly static]", "static"),
            ("twitch", "$[twitch static]", "static"),
            ("shake", "$[shake static]", "static"),
            ("spin", "$[spin static]", "static"),
            ("jump", "$[jump static]", "static"),
            ("bounce", "$[bounce static]", "static"),
            ("flip", "$[flip.v static]", "static"),
            ("x2", "$[x2 static]", "static"),
            ("x3", "$[x3 static]", "static"),
            ("x4", "$[x4 static]", "static"),
            ("font", "$[font.serif static]", "static"),
            ("blur", "$[blur static]", "static"),
            ("rainbow", "$[rainbow.speed=2s static]", "static"),
            ("sparkle", "$[sparkle static]", "static"),
            ("rotate", "$[rotate.deg=30 static]", "static"),
            ("position", "$[position.x=0.8,y=0.5 static]", "static"),
            ("scale", "$[scale.x=4,y=2 static]", "static"),
            ("foreground", "$[fg.color=f00 static]", "static"),
            ("background", "$[bg.color=ff0 static]", "static"),
            ("border", "$[border.style=dashed,width=2 static]", "static"),
            ("clickable", "$[clickable.ev=fixture static]", "static"),
        ]

        for item in cases {
            XCTAssertEqual(text(item.source), item.expected, item.syntax)
        }
    }

    func testNestingEscapedPlainTextAndExplicitNewlinesStayLossless() {
        XCTAssertEqual(
            text("$[border.width=2 outer $[spin inner **bold**]]"),
            "outer inner bold"
        )
        XCTAssertEqual(
            text(#"<plain>\**not bold** \$[spin still literal]</plain>"#),
            #"\**not bold** \$[spin still literal]"#
        )
        XCTAssertEqual(
            text("first\n<center>second</center>\n> third"),
            "first\nsecond\n▎ third"
        )
    }

    func testMotionFunctionsKeepNestedInteractiveContentWithoutExecutingEffects() {
        let rendered = MissCatNativeMFMRenderer.render(
            "$[spin.speed=5s $[tada :blobcat: @alice@example.test #SwiftUI https://example.test/path]]"
        )
        let links = rendered.runs.compactMap(\.link)

        XCTAssertEqual(
            String(rendered.characters),
            ":blobcat: @alice@example.test #SwiftUI https://example.test/path"
        )
        XCTAssertTrue(links.contains(URL(string: "misscat-mfm://mention/alice@example.test")!))
        XCTAssertTrue(links.contains(URL(string: "misscat-mfm://hashtag/SwiftUI")!))
        XCTAssertTrue(links.contains(URL(string: "https://example.test/path")!))
    }

    func testOfficialLinksAndRemoteCustomEmojiMarkersRemainIntact() {
        let rendered = MissCatNativeMFMRenderer.render(
            "[site](https://example.test/a) :local+emoji: :wave@remote.example:"
        )

        XCTAssertEqual(
            String(rendered.characters),
            "site :local+emoji: :wave@remote.example:"
        )
        XCTAssertTrue(rendered.runs.compactMap(\.link).contains(URL(string: "https://example.test/a")!))
        XCTAssertEqual(
            MissCatNativeMFMRenderer.accessibilityText(":local+emoji: :wave@remote.example:"),
            "local+emoji 絵文字 wave@remote.example 絵文字"
        )
    }

    func testPlainTagDisablesNestedFormattingAndRouting() {
        let rendered = MissCatNativeMFMRenderer.render(
            "<plain>**bold** @alice #SwiftUI `code` $[x2 large] :blobcat:</plain>"
        )

        XCTAssertEqual(
            String(rendered.characters),
            "**bold** @alice #SwiftUI `code` $[x2 large] :blobcat:"
        )
        XCTAssertTrue(rendered.runs.compactMap(\.link).isEmpty)
        XCTAssertTrue(rendered.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }

    func testInlineFormattingProducesAttributedStringSemantics() throws {
        let rendered = MissCatNativeMFMRenderer.render(
            "**bold** *italic* ~~strike~~ `code` <b>tag</b> <i>em</i> <s>gone</s>"
        )

        XCTAssertEqual(String(rendered.characters), "bold italic strike code tag em gone")
        XCTAssertTrue(try intent(for: "bold", in: rendered).contains(.stronglyEmphasized))
        XCTAssertTrue(try intent(for: "italic", in: rendered).contains(.emphasized))
        XCTAssertTrue(try intent(for: "strike", in: rendered).contains(.strikethrough))
        XCTAssertTrue(try intent(for: "code", in: rendered).contains(.code))
        XCTAssertTrue(try intent(for: "tag", in: rendered).contains(.stronglyEmphasized))
        XCTAssertTrue(try intent(for: "em", in: rendered).contains(.emphasized))
        XCTAssertTrue(try intent(for: "gone", in: rendered).contains(.strikethrough))
    }

    func testUnknownAndMalformedFunctionsRemainVisibleInsteadOfDroppingText() {
        XCTAssertEqual(text("$[future content]"), "$[future content]")
        XCTAssertEqual(text("before $[spin missing close"), "before $[spin missing close")
        XCTAssertEqual(text("$[spin $[jump nested]]"), "nested")
    }

    func testAnimatedEmojiFixtureExposesEveryFrameAndDurationForPlaybackFollowUp() throws {
        let animation = try MissCatCustomEmojiImageDecoder.decodeAnimation(Self.twoFrameGIFData)

        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(animation.frames.map(\.duration), [0.1, 0.2])
        XCTAssertEqual(animation.firstFrame.width, 1)
        XCTAssertEqual(animation.firstFrame.height, 1)
    }

    private func text(_ source: String) -> String {
        String(MissCatNativeMFMRenderer.render(source).characters)
    }

    private func intent(
        for substring: String,
        in rendered: AttributedString
    ) throws -> InlinePresentationIntent {
        let characters = String(rendered.characters)
        let stringRange = try XCTUnwrap(characters.range(of: substring))
        let attributedRange = try XCTUnwrap(Range(stringRange, in: rendered))
        return try XCTUnwrap(rendered[attributedRange].runs.first?.inlinePresentationIntent)
    }

    private static let twoFrameGIFData = Data([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
        0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
        0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00,
        0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x44, 0x01, 0x00,
        0x21, 0xF9, 0x04, 0x00, 0x14, 0x00, 0x00, 0x00,
        0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x44, 0x01, 0x00,
        0x3B,
    ])
}
