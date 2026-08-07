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

/// Actor-isolated queue between notification transport and the main-actor
/// router. Pushes may arrive before authentication restoration has completed.
public actor MissCatApplicationPushMailbox {
    public enum Rejection: Equatable, Sendable {
        case accountMismatch(
            expected: MissCatApplicationAccountID,
            received: MissCatApplicationAccountID
        )
    }

    public enum Admission: Equatable, Sendable {
        case queued
        case delivered
        case duplicate
        case rejected(Rejection)
    }

    public struct Snapshot: Equatable, Sendable {
        public let isRootReady: Bool
        public let expectedAccountID: MissCatApplicationAccountID?
        public let pendingCount: Int
        public let rejectedCount: Int
        public let duplicateCount: Int
        public let droppedCount: Int
        public let lastRejection: Rejection?
    }

    private let capacity: Int
    private var isRootReady = false
    private var expectedAccountID: MissCatApplicationAccountID?
    private var pending: [MissCatApplicationPush] = []
    private var seenIDs: [String] = []
    private var seenIDSet: Set<String> = []
    private var rejectedCount = 0
    private var duplicateCount = 0
    private var droppedCount = 0
    private var lastRejection: Rejection?

    public init(capacity: Int = 32) {
        self.capacity = max(1, capacity)
    }

    public func enqueue(_ push: MissCatApplicationPush) -> Admission {
        admit(push, recordsSeenID: true)
    }

    /// Re-admits a push if the application changed root state while awaiting
    /// the actor. The delivery ID is already recorded, so this bypasses only
    /// duplicate detection, never account validation.
    public func readmitAfterRootTransition(_ push: MissCatApplicationPush) -> Admission {
        if pending.contains(where: { $0.id == push.id }) { return .queued }
        return admit(push, recordsSeenID: false)
    }

    public func setRootUnready(expecting accountID: MissCatApplicationAccountID?) {
        isRootReady = false
        expectedAccountID = accountID
    }

    /// Activates delivery and returns matching queued pushes in FIFO order.
    /// Anything queued before session restoration for another account is
    /// rejected rather than silently crossing an account boundary.
    public func setRootReady(for accountID: MissCatApplicationAccountID) -> [MissCatApplicationPush] {
        isRootReady = true
        expectedAccountID = accountID
        var deliveries: [MissCatApplicationPush] = []
        for push in pending {
            if push.accountID == accountID {
                deliveries.append(push)
            } else {
                recordRejection(expected: accountID, received: push.accountID)
            }
        }
        pending.removeAll(keepingCapacity: true)
        return deliveries
    }

    public func clear() {
        isRootReady = false
        expectedAccountID = nil
        pending.removeAll()
        seenIDs.removeAll()
        seenIDSet.removeAll()
        rejectedCount = 0
        duplicateCount = 0
        droppedCount = 0
        lastRejection = nil
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            isRootReady: isRootReady,
            expectedAccountID: expectedAccountID,
            pendingCount: pending.count,
            rejectedCount: rejectedCount,
            duplicateCount: duplicateCount,
            droppedCount: droppedCount,
            lastRejection: lastRejection
        )
    }

    private func admit(
        _ push: MissCatApplicationPush,
        recordsSeenID: Bool
    ) -> Admission {
        if recordsSeenID {
            guard seenIDSet.insert(push.id).inserted else {
                duplicateCount += 1
                return .duplicate
            }
            seenIDs.append(push.id)
            trimSeenIDs()
        }

        if let expectedAccountID, push.accountID != expectedAccountID {
            return .rejected(recordRejection(expected: expectedAccountID, received: push.accountID))
        }

        if isRootReady { return .delivered }
        if pending.count == capacity {
            pending.removeFirst()
            droppedCount += 1
        }
        pending.append(push)
        return .queued
    }

    @discardableResult
    private func recordRejection(
        expected: MissCatApplicationAccountID,
        received: MissCatApplicationAccountID
    ) -> Rejection {
        let rejection = Rejection.accountMismatch(expected: expected, received: received)
        rejectedCount += 1
        lastRejection = rejection
        return rejection
    }

    private func trimSeenIDs() {
        let maximum = capacity * 4
        guard seenIDs.count > maximum else { return }
        let expired = Array(seenIDs.prefix(seenIDs.count - maximum))
        seenIDs.removeFirst(expired.count)
        seenIDSet.subtract(expired)
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
    public let pushMailbox: MissCatApplicationPushMailbox

    @ObservationIgnored private let sessionProvider: any MissCatApplicationSessionProviding
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var transitionGeneration = 0
    @ObservationIgnored private var stableSession: MissCatApplicationSession?

    public init(
        sessionProvider: any MissCatApplicationSessionProviding,
        router: MissCatApplicationRouter? = nil,
        pushMailbox: MissCatApplicationPushMailbox = MissCatApplicationPushMailbox()
    ) {
        self.sessionProvider = sessionProvider
        self.router = router ?? MissCatApplicationRouter()
        self.pushMailbox = pushMailbox
    }

    deinit {
        transitionTask?.cancel()
    }

    public func restore() async {
        let generation = beginTransition()
        phase = .launching
        lastErrorMessage = nil
        await pushMailbox.setRootUnready(expecting: nil)
        guard isGeneration(generation) else { return }

        let task = Task { @MainActor [weak self, sessionProvider] in
            do {
                let session = try await sessionProvider.restoreSession()
                guard let self, self.isCurrent(generation) else { return }
                if let session {
                    await self.applyAuthenticated(session)
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
        await pushMailbox.setRootUnready(expecting: accountID)
        guard isGeneration(generation) else { return }

        let task = Task { @MainActor [weak self, sessionProvider] in
            do {
                let session = try await sessionProvider.switchSession(to: accountID)
                guard session.currentAccount.id == accountID else {
                    throw MissCatApplicationSessionError.accountIdentityMismatch
                }
                guard let self, self.isCurrent(generation) else { return }
                await self.applyAuthenticated(session)
            } catch is CancellationError {
                guard let self, self.isGeneration(generation) else { return }
                await self.restoreAfterFailedTransition(current)
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.lastErrorMessage = Self.message(for: error)
                await self.restoreAfterFailedTransition(current)
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
        await pushMailbox.setRootUnready(expecting: nil)
        guard isGeneration(generation) else { return }

        let task = Task { @MainActor [weak self, sessionProvider] in
            do {
                try await sessionProvider.signOut(accountID: current.currentAccount.id)
                guard let self, self.isCurrent(generation) else { return }
                self.stableSession = nil
                self.phase = .signedOut
                self.router.clearForSignOut()
                await self.pushMailbox.clear()
            } catch is CancellationError {
                guard let self, self.isGeneration(generation) else { return }
                await self.restoreAfterFailedTransition(current)
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.lastErrorMessage = Self.message(for: error)
                await self.restoreAfterFailedTransition(current)
            }
        }
        transitionTask = task
        await task.value
        finishTransition(generation)
    }

    @discardableResult
    public func receivePush(
        _ push: MissCatApplicationPush
    ) async -> MissCatApplicationPushMailbox.Admission {
        let generation = transitionGeneration
        let admission = await pushMailbox.enqueue(push)
        guard admission == .delivered else { return admission }

        if generation == transitionGeneration,
           stableSession?.currentAccount.id == push.accountID,
           case .authenticated = phase
        {
            router.handleDeliveredPush(push)
            return admission
        }

        let readmission = await pushMailbox.readmitAfterRootTransition(push)
        if readmission == .delivered,
           stableSession?.currentAccount.id == push.accountID,
           case .authenticated = phase
        {
            router.handleDeliveredPush(push)
        }
        return readmission
    }

    public func cancelPendingTransition() async {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        restoreStablePhase()
        if let stableSession {
            let deliveries = await pushMailbox.setRootReady(for: stableSession.currentAccount.id)
            deliveries.forEach(router.handleDeliveredPush)
        } else {
            await pushMailbox.setRootUnready(expecting: nil)
        }
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

    private func applyAuthenticated(_ session: MissCatApplicationSession) async {
        stableSession = session
        router.activate(session)
        phase = .authenticated(session)
        let deliveries = await pushMailbox.setRootReady(for: session.currentAccount.id)
        deliveries.forEach(router.handleDeliveredPush)
    }

    private func restoreAfterFailedTransition(_ session: MissCatApplicationSession) async {
        stableSession = session
        phase = .authenticated(session)
        let deliveries = await pushMailbox.setRootReady(for: session.currentAccount.id)
        deliveries.forEach(router.handleDeliveredPush)
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
