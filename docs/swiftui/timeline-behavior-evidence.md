# Timeline behavior evidence

This document maps the source-level evidence for `HOME-01`, `HOME-02`,
`TL-01`, and `TL-02`. It complements the acceptance matrix; it does not replace
the required newest-iOS UI/E2E run or visual evidence.

## HOME-01 — synchronized shell pager

| Contract | Unit/source evidence | UI/E2E source evidence |
| --- | --- | --- |
| One state for tap and swipe | `MissCatFeedStoreTests.testTimelineSelectionUsesOneStateForTapSwipeAndReverseSwipe` and `testTimelineSelectionHandlesRapidChangesAndPageReplacement` | `MissCatShellFeedUITests.testTimelineTabsSupportTapAndSwipe`, `testFourConfiguredTimelineTabsSupportOrdinaryTapSwipeAndBoundaries`, and `testOrdinaryProductionRootOwnsShellRoutesAndAccountGeneration` |
| Explicit first/last boundary behavior | `MissCatFeedStoreTests.testTimelineSelectionClampsEdgeSwipesAndRejectsUnknownTabs` | Both pager UI tests above assert an extra swipe at each edge does not wrap |
| Five footer routes and reselect-to-top | `MissCatFeedStoreTests.testFiveFooterDestinationsShareSelectionAndReselectContract` and `testShellStoreEmitsOnlyHomeAndNotificationScrollToTopSignals` | `MissCatShellFeedUITests.testFooterAccountPopoverAndCompositeScrollRestoration` |

## HOME-02 — configured tabs, ownership, and restoration

| Contract | Unit/source evidence | UI/E2E source evidence |
| --- | --- | --- |
| Add, delete, reorder, rename, owner change, defaults | `MissCatSettingsAccountsTests.testLoadAndEditPreserveLegacyThemeContract`, `testRemovingEveryTabRestoresExactLegacyDefaults`, `testChangingHomeOwnerUpdatesDisplayName`, and `testLoadRepairsInvalidOwnersWithoutChangingOrderedTabIdentityFields` | `MissCatShellFeedUITests.testAccountsNativeNavigationSwitchDeletionAndRetry` and `testLastTabOwningAccountDeletionKeepsRequiredRecoveryOnProductionBridge` |
| Composite account identity and page ownership | `MissCatFeedStoreTests.testAccountScopeNormalizesInstanceAndNeverCollidesAcrossInstances`, `testPageOwnerResolutionUsesCompositeAccountIdentity`, and `testRemovedAccountRepositoryCannotBeReusedAfterConfigurationChange` | `MissCatShellFeedUITests.testFooterAccountPopoverAndCompositeScrollRestoration` |
| Rapid switching cannot persist stale selection | `MissCatFeedStoreTests.testRapidTimelineSelectionSerializesNonCooperativePersistence`, `testShellStorePersistsTapAndSwipeAgainstInstanceUserScope`, and `testShellStoreRejectsLateNonCooperativeAccountSwitch` | The four-tab and ordinary production pager tests exercise tap, forward swipe, reverse swipe, and boundaries |
| Per-tab/per-account scroll position | `MissCatFeedStoreTests.testScrollPositionsRestoreByCompositeAccountIdentity` | `MissCatShellFeedUITests.testFooterAccountPopoverAndCompositeScrollRestoration` |

## TL-01 — REST timelines

| Contract | Unit/source evidence | UI/E2E source evidence |
| --- | --- | --- |
| Exact Home/Local/Social/Global endpoint and flags | `MissCatFeedRepositoryContractTests.testModernTimelinesUseAccountTokenAndDecodeDictionaryFields` | Ordinary and four-tab pager journeys load each configured feed |
| Credential remains bound to repository/account | `MissCatFeedRepositoryContractTests.testTimelineRepositoriesNeverSubstituteAnotherAccountsCredential` and `MissCatFeedStoreTests.testRemovedAccountRepositoryCannotBeReusedAfterConfigurationChange` | `MissCatShellFeedUITests.testOrdinaryProductionRootOwnsShellRoutesAndAccountGeneration` |
| Initial, empty, error, retry | `MissCatFeedStoreTests.testInitialFetchPublishesNotesAndRequestScope` and `testInitialEmptyFailureAndRetryReachTerminalStates` | `MissCatShellFeedUITests.testEmptyLoadingErrorOfflineAndShellBannerFixtures` |
| Refresh, pagination, dedupe, exactly once, read-error recovery | `MissCatFeedStoreTests.testRefreshPrependsNewNotesWithoutDuplicates`, `testPaginationUsesLastItemAndAppendsUniqueNotes`, and `testRapidPaginationIsExactlyOnceAndSuccessfulRetryClearsReadError` | `MissCatShellFeedUITests.testTimelineRefreshPaginationActionsAndDetailNavigation` |

The explicit request keys match the current Misskey endpoint schemas pinned at
`00f66349766dc61298c66129ded5fdeb29e93f41`:

- [`notes/timeline`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/timeline.ts)
- [`notes/local-timeline`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/local-timeline.ts)
- [`notes/hybrid-timeline`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/hybrid-timeline.ts)
- [`notes/global-timeline`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/global-timeline.ts)

## TL-02 — streaming and teardown

| Contract | Unit/integration evidence |
| --- | --- |
| Correct channel and secret-safe connection | `MissCatFeedRepositoryContractTests.testStreamingUsesSecretSafeRequestAndExactConnectAcknowledgement` and `testStreamingMapsAllCurrentTimelineChannelNames` |
| Insert and per-note subscription | `testStreamingDecodesCurrentDictionaryNoteEnvelopeAndSubscribesToIt` |
| Reaction, unreaction, delete, poll and self/other identity | `testStreamingDecodesEveryCurrentNoteUpdatedVariantAndIsMine`, `MissCatFeedStoreTests.testRealtimeInsertReactionAndDeleteUpdateLoadedFeed`, `testOtherUsersReactionEventsPreserveMyReactionSelection`, and `testRealtimeDuplicateInsertAndPollVoteReconcileOneRow` |
| Reconnect, catch-up, replacement/insert dedupe, stale-socket rejection | `testReconnectResubscribesThenPerformsRESTResyncAndIgnoresStaleSocket` |
| Malformed/cross-channel isolation | `testSiblingStreamsIgnoreOtherChannelAndCapturedNoteEvents` and `testMalformedUnknownAndWrongIdentifiersAreIgnored` |
| Tab/account teardown | `testStreamingTerminationUnsubscribesDisconnectsAndClosesSocket`, `MissCatFeedStoreTests.testLoadedFeedRestartsRealtimeAfterViewLifetimeCancellation`, and `testRemovedAccountRepositoryCannotBeReusedAfterConfigurationChange` |

## Audit fixes

- Timeline requests now state current endpoint semantics explicitly instead of
  inheriting mutable server defaults.
- Read retries clear their own stale error after succeeding while retaining a
  pending retryable write error.
- Another user's reaction/unreaction no longer clears the signed-in user's
  selected reaction styling.
- Rapid tab selections serialize persistence, so a canceled but
  non-cooperative older write cannot win the final stored state.
- Repository lookup is limited to the current authorized account snapshot and
  cached repositories are released when an account disappears.

The integration branch must still execute the cited UI/E2E tests on the newest
iOS runtime. This audit intentionally did not boot, install to, or read data
from any Simulator.
