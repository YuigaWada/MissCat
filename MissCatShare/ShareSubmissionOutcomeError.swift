import Foundation

/// Shared by the app API and extension UI without making the extension-only
/// core depend on an app-target concrete error type.
protocol ShareSubmissionOutcomeError: Error {
    var isSubmissionOutcomeUnknown: Bool { get }
}
