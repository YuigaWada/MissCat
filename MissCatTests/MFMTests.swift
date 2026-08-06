//
//  MFMTests.swift
//  MissCatTests
//
//  Created by Yuiga Wada on 2020/04/15.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

@testable import MissCat
import UIKit
import XCTest

class MFMTests: XCTestCase {
    private let mockUser: SecureUser = .init(userId: "", username: "", instance: "", apiKey: nil)
    // Never replace this with `UIFont()`: its inherited empty initializer does
    // not create the CoreText backing that MFMEngine reads on current iOS.
    private let testFont = UIFont.systemFont(ofSize: 15)
    override func setUp() {}
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    // MARK: Normal Linking
    
    func testLinkHttps() {
        let https = "https://misskey.io"
        let preHttps = https.mfmPreTransform()
        let attributedHttps = preHttps.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedHttps)
        XCTAssertEqual(attributedHttps!.cleanup(), "https://misskey.io")
    }
    
    func testLinkHttp() {
        let http = "http://misskey.io"
        let preHttp = http.mfmPreTransform()
        let attributedHttp = preHttp.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedHttp)
        XCTAssertEqual(attributedHttp!.cleanup(), "http://misskey.io")
    }
    
    func testLinkHttpsMd() {
        let httpsMd = "[MISSKEY1](https://misskey.io)"
        let preHttpsMd = httpsMd.mfmPreTransform()
        let attributedHttpsMd = preHttpsMd.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedHttpsMd)
        XCTAssertEqual(attributedHttpsMd!.cleanup(), "MISSKEY1")
    }
    
    func testLinkHttpMd() {
        let httpMd = "[MISSKEY2](http://misskey.io)"
        let preHttpMd = httpMd.mfmPreTransform()
        let attributedHttpMd = preHttpMd.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedHttpMd)
        XCTAssertEqual(attributedHttpMd!.cleanup(), "MISSKEY2")
    }
    
    // MARK: Linking Hashtag
    
    func testHyperHashtag() {
        let tag = "#TEST"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "#TEST")
    }
    
    func testHyperJPHashtag() {
        let tag = "#てすと"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "#てすと")
    }
    
    // MARK: Linking User
    
    func testHyperUser() {
        let user = "@wada@misskey.io"
        let pre = user.mfmPreTransform()
        let attributed = pre.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributed)
        XCTAssertEqual(attributed!.cleanup(), "@wada@misskey.io")
    }
    
    // MARK: Ignored Markdown
    
    func testIgnoreMotionTag() {
        let tag = "<motion>test test</motion>"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }
    
    func testIgnoreFlipTag() {
        let tag = "<flip>test test</flip>"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }
    
    func testIgnoreSpinTag() {
        let tag = "<spin>test test</spin>"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }
    
    func testIgnoreJumpTag() {
        let tag = "<jump>test test</jump>"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }
    
    func testIgnoreSmallTag() {
        let tag = "<small>test test</small>"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }
    
    func testIgnoreThreeAsta() {
        let tag = "***test test***"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }
    
    func testIgnoreThreeBrackets() {
        let tag = "(((test test)))"
        let preTag = tag.mfmPreTransform()
        let attributedTag = preTag.mfmTransform(owner: mockUser, font: testFont).attributed?.string
        
        XCTAssertNotNil(attributedTag)
        XCTAssertEqual(attributedTag!.cleanup(), "test test")
    }

    func testGeneratePlaneStringWithValidHelveticaFont() {
        guard let font = UIFont(name: "Helvetica", size: 19) else {
            return XCTFail("Helvetica must be available on iOS")
        }
        let expectedFamily = font.familyName
        let expectedSize = font.pointSize

        let attributed = MFMEngine.generatePlaneString(string: "font", font: font)
        let renderedFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont

        XCTAssertEqual(attributed.string, "font")
        XCTAssertEqual(font.familyName, expectedFamily)
        XCTAssertEqual(font.pointSize, expectedSize, accuracy: 0.01)
        XCTAssertEqual(renderedFont?.familyName, expectedFamily)
        XCTAssertGreaterThan(renderedFont?.pointSize ?? 0, 0)
    }
    
    // MARK: CustomEmojis
    
//    func testCustomEmoji() {
//        let text = "test :ablobdundundun: test"
//        let pre = text.mfmPreTransform()
//        let attributed = pre.mfmTransform(owner: mockUser,font: .init()).attributed?.string
//
//        XCTAssertNotNil(attributed)
//        XCTAssertEqual(attributed!.cleanup(), "test test")
//    }
//
//    func testMultipleCustomEmojis() {
//        let text = "chrome::chrome:, aftereffects::aftereffects:,しゅいろ::syuilo:"
//        let pre = text.mfmPreTransform()
//        let attributed = pre.mfmTransform(owner: mockUser,font: .init()).attributed?.string
//
//        XCTAssertNotNil(attributed)
//        XCTAssertEqual(attributed!.cleanup(), "chrome:, aftereffects:,しゅいろ:")
//    }
}

private extension String {
    /// NSTextAttachmentを添付してることによって生じる\{ef}を削除
    func cleanup() -> String {
        return replacingOccurrences(of: "\u{fffc}",
                                    with: "",
                                    options: NSString.CompareOptions.literal,
                                    range: nil)
    }
}
