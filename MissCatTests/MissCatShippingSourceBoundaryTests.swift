import Foundation
import XCTest

final class MissCatShippingSourceBoundaryTests: XCTestCase {
    func testAppShippingSourcesExcludeLegacyScreenAndDependencyGraph() throws {
        let project = try source(named: "MissCat.xcodeproj/project.pbxproj")
        let appSources = try objectBlock(
            identifier: "8D4A2A0E237437BE00503685",
            in: project
        )
        let sourceNames = try swiftSourceNames(in: appSources)

        XCTAssertEqual(sourceNames.count, 62)
        XCTAssertTrue(sourceNames.contains("MissCatNativeAPI.swift"))
        XCTAssertTrue(sourceNames.contains("MissCatCameraCapture.swift"))
        for forbiddenMembership in [
            "AppDelegate.swift in Sources",
            "ApiKeyManager.swift in Sources",
            "MisscatApi.swift in Sources",
            "ViewController.swift in Sources",
            "ViewModel.swift in Sources",
            "MFMEngine.swift in Sources",
            "EmojiHandler.swift in Sources",
            "Entity.swift in Sources",
            "RxEureka.swift in Sources",
            "SceneDelegate.swift in Sources",
            "MisskeyKit+MissCat.swift in Sources",
        ] {
            XCTAssertFalse(appSources.contains(forbiddenMembership), forbiddenMembership)
        }

        let repositorySources = try repositorySwiftSources()
        for sourceName in sourceNames {
            let matches = repositorySources.filter { $0.lastPathComponent == sourceName }
            let sourceURL = try XCTUnwrap(
                matches.count == 1 ? matches.first : nil,
                "Shipping source must resolve uniquely: \(sourceName), matches=\(matches)"
            )
            let relativePath = sourceURL.path.replacingOccurrences(
                of: repositoryRoot.path + "/",
                with: ""
            )
            XCTAssertFalse(
                legacySourcePrefixes.contains { relativePath.hasPrefix($0) },
                "Legacy source remains in the App target: \(relativePath)"
            )
            try assertNoLegacyDependencyOrLoader(in: sourceURL)
        }
    }

    func testShareAndDependencyFreeBoundariesStaySlim() throws {
        let project = try source(named: "MissCat.xcodeproj/project.pbxproj")
        let shareSources = try objectBlock(
            identifier: "8D1A4BF624DD7BFF00EFD826",
            in: project
        )
        XCTAssertEqual(
            Set(try swiftSourceNames(in: shareSources)),
            Set([
                "MissCatNativeComposeAPI.swift",
                "MissCatNativeKeychainStore.swift",
                "ShareViewController.swift",
                "ShareComposerView.swift",
                "ShareCore.swift",
                "ShareInputLoader.swift",
                "UserModel.swift",
                "PostModel.swift",
            ])
        )
        let absentPaths = [
            "Podfile",
            "Podfile.lock",
            "Pods",
            "MissCat/GoogleService-Info.plist",
            "MissCat/Resources/ThirdPartyAcknowledgements.plist",
            "config/third-party-acknowledgements.lock.json",
        ]
        for path in absentPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                "Retired dependency artifact remains: \(path)"
            )
        }
        for retiredReference in [
            "Pods_MissCat",
            "Pods-MissCat",
            "[CP]",
            "PODS_ROOT",
            "baseConfigurationReference",
            "Firebase",
            "MisskeyKit",
            "ApiKeyManager",
            "Starscream",
            "ThirdPartyAcknowledgements",
        ] {
            XCTAssertFalse(project.contains(retiredReference), retiredReference)
        }
    }

    func testUIKitShippingSourcesExposeOnlyApprovedOSAdapterSymbols() throws {
        let project = try source(named: "MissCat.xcodeproj/project.pbxproj")
        let appSources = try objectBlock(
            identifier: "8D4A2A0E237437BE00503685",
            in: project
        )
        let sourceNames = try swiftSourceNames(in: appSources)
        let repositorySources = try repositorySwiftSources()
        var UIKitSymbolsBySource: [String: Set<String>] = [:]

        for sourceName in sourceNames {
            let sourceURL = try XCTUnwrap(
                repositorySources.first { $0.lastPathComponent == sourceName }
            )
            let contents = try String(contentsOf: sourceURL, encoding: .utf8)
            guard contents.split(separator: "\n").contains("import UIKit") else { continue }
            UIKitSymbolsBySource[sourceName] = try UIKitSymbols(in: contents)
        }

        XCTAssertEqual(
            UIKitSymbolsBySource,
            [
                "MissCatSystemClipboardWriter.swift": ["UIPasteboard"],
            ]
        )

        let shippingSource = try sourceNames.map { sourceName in
            try String(
                contentsOf: XCTUnwrap(
                    repositorySources.first { $0.lastPathComponent == sourceName }
                ),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        for deferredTransportSymbol in [
            "import FirebaseCore",
            "import FirebaseMessaging",
            "MessagingDelegate",
            "registerForRemoteNotifications",
            "MissCatApplicationPushIngress",
            "MissCatApplicationPushMailbox",
            "MissCatPushEnvelope",
        ] {
            XCTAssertFalse(shippingSource.contains(deferredTransportSymbol), deferredTransportSymbol)
        }

        let clipboard = try source(
            named: "MissCat/Others/Platform/MissCatSystemClipboardWriter.swift"
        )
        XCTAssertEqual(clipboard.components(separatedBy: "public func ").count - 1, 1)
        XCTAssertTrue(clipboard.contains("public func write("))
        XCTAssertFalse(clipboard.contains("func read("))
    }

    private func assertNoLegacyDependencyOrLoader(in sourceURL: URL) throws {
        let contents = try String(contentsOf: sourceURL, encoding: .utf8)
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            XCTAssertFalse(
                forbiddenImports.contains(trimmed),
                "Legacy import in \(sourceURL.lastPathComponent): \(trimmed)"
            )
            guard !trimmed.hasPrefix("//") else { continue }
            XCTAssertFalse(
                trimmed.contains("UIStoryboard(") || trimmed.contains("UINib("),
                "Legacy loader in \(sourceURL.lastPathComponent): \(trimmed)"
            )
        }
    }

    private func repositorySwiftSources() throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: repositoryRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )
        return enumerator.compactMap { element in
            guard let url = element as? URL, url.pathExtension == "swift" else { return nil }
            let relativePath = url.path.replacingOccurrences(
                of: repositoryRoot.path + "/",
                with: ""
            )
            guard !relativePath.hasPrefix("Pods/") else { return nil }
            return url
        }
    }

    private func swiftSourceNames(in block: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"/\* ([^*]+\.swift) in Sources \*/"#
        )
        let range = NSRange(block.startIndex..<block.endIndex, in: block)
        return expression.matches(in: block, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: block) else { return nil }
            return String(block[range])
        }
    }

    private func source(named relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func objectBlock(identifier: String, in project: String) throws -> String {
        let marker = "\t\t\(identifier) /* Sources */ = {"
        let start = try XCTUnwrap(project.range(of: marker))
        let suffix = project[start.lowerBound...]
        let end = try XCTUnwrap(suffix.range(of: "\n\t\t};"))
        return String(suffix[..<end.upperBound])
    }

    private func UIKitSymbols(in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(pattern: #"\bUI[A-Z][A-Za-z0-9_]*\b"#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range, in: source) else { return nil }
            return String(source[range])
        }.filter { $0 != "UIKit" })
    }

    private var legacySourcePrefixes: [String] {
        [
            "MissCat/Entity/",
            "MissCat/MFMEngine/",
            "MissCat/Model/",
            "MissCat/View/",
            "MissCat/ViewModel/",
        ]
    }

    private var forbiddenImports: Set<String> {
        Set([
            "import APNGKit",
            "import Agrume",
            "import ChromaColorPicker",
            "import Eureka",
            "import FloatingPanel",
            "import Gifu",
            "import MessageKit",
            "import MisskeyKit",
            "import PolioPager",
            "import RxCocoa",
            "import RxDataSources",
            "import RxSwift",
            "import SVGKit",
            "import SkeletonView",
            "import SwiftLinkPreview",
            "import Starscream",
            "import XLPagerTabStrip",
            "import iOSPhotoEditor",
        ])
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
