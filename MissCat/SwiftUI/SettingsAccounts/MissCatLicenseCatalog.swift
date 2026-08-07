import Foundation

/// Provides licenses for third-party packages actually linked by the app.
/// The dependency-free build currently has no package entries.
enum MissCatLicenseCatalog {
    static let dependencyNames: [String] = []

    static func acknowledgements(in _: Bundle = .main) -> [String: String] { [:] }

    static func entries(in bundle: Bundle = .main) -> [MissCatLicenseEntry] {
        acknowledgements(in: bundle)
            .map { MissCatLicenseEntry(name: $0.key, text: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
