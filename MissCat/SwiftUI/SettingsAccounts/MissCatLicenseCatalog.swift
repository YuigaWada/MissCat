import Foundation

/// Provides the third-party package licenses that are actually linked by the app.
/// The dependency-free build currently has no package acknowledgement entries.
enum MissCatLicenseCatalog {
    static let dependencyNames: [String] = []

    static func acknowledgements(in bundle: Bundle = .main) -> [String: String] {
        guard let url = bundle.url(
            forResource: "ThirdPartyAcknowledgements",
            withExtension: "plist"
        ),
        let data = try? Data(contentsOf: url),
        let propertyList = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ),
        let root = propertyList as? [String: Any],
        let specifiers = root["PreferenceSpecifiers"] as? [[String: Any]]
        else { return [:] }

        let required = Set(dependencyNames)
        return specifiers.reduce(into: [String: String]()) { result, specifier in
            guard let title = specifier["Title"] as? String,
                  required.contains(title),
                  let text = specifier["FooterText"] as? String
            else { return }
            result[title] = text
        }
    }

    static func entries(in bundle: Bundle = .main) -> [MissCatLicenseEntry] {
        acknowledgements(in: bundle)
            .map { MissCatLicenseEntry(name: $0.key, text: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
