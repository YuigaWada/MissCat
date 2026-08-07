import Foundation
import XCTest

final class MissCatNativeKeychainProjectBoundaryTests: XCTestCase {
    func testSecurityStoreOwnsItsBoundaryOutsideComposeAPI() throws {
        let store = try source(named: "MissCat/Others/Security/MissCatNativeKeychainStore.swift")
        let compose = try source(named: "MissCat/Others/App/MissCatNativeComposeAPI.swift")
        let imports = store.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("import ") else { return nil }
            return String(line.dropFirst("import ".count))
        }

        XCTAssertEqual(Set(imports), Set(["Foundation", "Security"]))
        XCTAssertTrue(store.contains("struct MissCatNativeKeychainStore"))
        XCTAssertFalse(compose.contains("MissCatNativeKeychainStore"))
        XCTAssertFalse(compose.contains("import Security"))
    }

    func testSecurityStoreHasExactlyOneAppAndShareSourceMembership() throws {
        let project = try source(named: "MissCat.xcodeproj/project.pbxproj")
        let appSources = try objectBlock(
            identifier: "8D4A2A0E237437BE00503685",
            in: project
        )
        let shareSources = try objectBlock(
            identifier: "8D1A4BF624DD7BFF00EFD826",
            in: project
        )
        let membership = "MissCatNativeKeychainStore.swift in Sources"

        XCTAssertEqual(occurrences(of: membership, in: appSources), 1)
        XCTAssertEqual(occurrences(of: membership, in: shareSources), 1)
        XCTAssertEqual(
            occurrences(
                of: "/* \(membership) */ = {isa = PBXBuildFile",
                in: project
            ),
            2
        )
        XCTAssertEqual(
            occurrences(
                of: "/* MissCatNativeKeychainStore.swift */ = {isa = PBXFileReference",
                in: project
            ),
            1
        )
        XCTAssertEqual(occurrences(of: "path = Security;", in: project), 1)
    }

    func testShareTargetEnforcesExtensionSafeSecurityBoundary() throws {
        let project = try source(named: "MissCat.xcodeproj/project.pbxproj")
        for configuration in [
            "8D1A4C0624DD7BFF00EFD826",
            "8D1A4C0724DD7BFF00EFD826",
        ] {
            let block = try objectBlock(identifier: configuration, in: project)
            XCTAssertTrue(block.contains("APPLICATION_EXTENSION_API_ONLY = YES;"))
        }

        let store = try source(named: "MissCat/Others/Security/MissCatNativeKeychainStore.swift")
        for forbiddenAPI in [
            "import UIKit",
            "UIApplication",
            "NS_EXTENSION_UNAVAILABLE_IOS",
            "@available(iOSApplicationExtension, unavailable)",
        ] {
            XCTAssertFalse(store.contains(forbiddenAPI), "Forbidden extension API: \(forbiddenAPI)")
        }
    }

    private func source(named relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func objectBlock(identifier: String, in project: String) throws -> String {
        let marker = "\t\t\(identifier) /*"
        let start = try XCTUnwrap(project.range(of: marker))
        let suffix = project[start.lowerBound...]
        let end = try XCTUnwrap(suffix.range(of: "\n\t\t};"))
        return String(suffix[..<end.upperBound])
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let match = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = match.upperBound..<haystack.endIndex
        }
        return count
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
