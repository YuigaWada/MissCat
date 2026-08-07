import Foundation
import Observation

public protocol MissCatApplicationSessionProviding: Sendable {
    func restoreSession() async throws -> MissCatApplicationSession?
    func switchSession(to accountID: MissCatApplicationAccountID) async throws -> MissCatApplicationSession
    func signOut(accountID: MissCatApplicationAccountID) async throws
}

public enum MissCatApplicationSessionError: LocalizedError, Equatable, Sendable {
    case accountIdentityMismatch

    public var errorDescription: String? {
        switch self {
        case .accountIdentityMismatch:
            "The selected account did not match the restored session."
        }
    }
}

/// Owns account/root lifecycle and rejects results from canceled or superseded
/// operations, including providers that do not cooperatively throw cancellation.
@MainActor
@Observable
public final class MissCatApplicationRootStore {
    public private(set) var phase: MissCatApplicationRootPhase = .launching
    public private(set) var lastErrorMessage: String?

    public let router: MissCatApplicationRouter
    @ObservationIgnored private let sessionProvider: any MissCatApplicationSessionProviding
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var transitionGeneration = 0
    @ObservationIgnored private var stableSession: MissCatApplicationSession?

    public init(
        sessionProvider: any MissCatApplicationSessionProviding,
        router: MissCatApplicationRouter? = nil
    ) {
        self.sessionProvider = sessionProvider
        self.router = router ?? MissCatApplicationRouter()
    }

    deinit {
        transitionTask?.cancel()
    }

    public func restore() async {
        let generation = beginTransition()
        phase = .launching
        lastErrorMessage = nil
        guard isGeneration(generation) else { return }

        let task = Task { @MainActor [weak self, sessionProvider] in
            do {
                let session = try await sessionProvider.restoreSession()
                guard let self, self.isCurrent(generation) else { return }
                if let session {
                    self.applyAuthenticated(session)
                } else {
                    self.stableSession = nil
                    self.phase = .signedOut
                    self.router.clearForSignOut()
                }
            } catch is CancellationError {
                guard let self, self.isGeneration(generation) else { return }
                self.restoreStablePhase()
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.stableSession = nil
                self.router.clearForSignOut()
                self.phase = .failed(message: Self.message(for: error))
                self.lastErrorMessage = Self.message(for: error)
            }
        }
        transitionTask = task
        await task.value
        finishTransition(generation)
    }

    public func switchAccount(to accountID: MissCatApplicationAccountID) async {
        guard let current = stableSession, current.currentAccount.id != accountID else { return }
        let generation = beginTransition()
        phase = .switching(current: current, target: accountID)
        lastErrorMessage = nil
        guard isGeneration(generation) else { return }

        let task = Task { @MainActor [weak self, sessionProvider] in
            do {
                let session = try await sessionProvider.switchSession(to: accountID)
                guard session.currentAccount.id == accountID else {
                    throw MissCatApplicationSessionError.accountIdentityMismatch
                }
                guard let self, self.isCurrent(generation) else { return }
                self.applyAuthenticated(session)
            } catch is CancellationError {
                guard let self, self.isGeneration(generation) else { return }
                self.restoreAfterFailedTransition(current)
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.lastErrorMessage = Self.message(for: error)
                self.restoreAfterFailedTransition(current)
            }
        }
        transitionTask = task
        await task.value
        finishTransition(generation)
    }

    public func signOut() async {
        guard let current = stableSession else { return }
        let generation = beginTransition()
        phase = .signingOut(current: current)
        lastErrorMessage = nil
        guard isGeneration(generation) else { return }

        let task = Task { @MainActor [weak self, sessionProvider] in
            do {
                try await sessionProvider.signOut(accountID: current.currentAccount.id)
                guard let self, self.isCurrent(generation) else { return }
                self.stableSession = nil
                self.phase = .signedOut
                self.router.clearForSignOut()
            } catch is CancellationError {
                guard let self, self.isGeneration(generation) else { return }
                self.restoreAfterFailedTransition(current)
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.lastErrorMessage = Self.message(for: error)
                self.restoreAfterFailedTransition(current)
            }
        }
        transitionTask = task
        await task.value
        finishTransition(generation)
    }

    public func cancelPendingTransition() async {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        restoreStablePhase()
    }

    public func dismissError() {
        lastErrorMessage = nil
    }

    private func beginTransition() -> Int {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        return transitionGeneration
    }

    private func finishTransition(_ generation: Int) {
        guard transitionGeneration == generation else { return }
        transitionTask = nil
    }

    private func isGeneration(_ generation: Int) -> Bool {
        transitionGeneration == generation
    }

    private func isCurrent(_ generation: Int) -> Bool {
        transitionGeneration == generation && !Task.isCancelled
    }

    private func applyAuthenticated(_ session: MissCatApplicationSession) {
        stableSession = session
        router.activate(session)
        phase = .authenticated(session)
    }

    private func restoreAfterFailedTransition(_ session: MissCatApplicationSession) {
        stableSession = session
        phase = .authenticated(session)
    }

    private func restoreStablePhase() {
        if let stableSession {
            phase = .authenticated(stableSession)
        } else if case .launching = phase {
            phase = .launching
        } else {
            phase = .signedOut
        }
    }

    private static func message(for error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "The application session could not be updated." : trimmed
    }
}
