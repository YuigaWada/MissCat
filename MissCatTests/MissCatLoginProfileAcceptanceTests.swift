import XCTest
@testable import MissCat

final class MissCatProfileNavigationAcceptanceTests: XCTestCase {
    func testSearchResultRelationshipAndNestedProfileRemainInTypedSwiftUIPath() {
        var state = MissCatProfileNavigationState()

        state.openProfile("fixture-target")
        state.openUserList(.followers(userID: "fixture-target"))
        state.openProfile("fixture-friend")

        XCTAssertEqual(
            state.path,
            [
                .profile(userID: "fixture-target"),
                .userList(.followers(userID: "fixture-target")),
                .profile(userID: "fixture-friend")
            ]
        )
        XCTAssertTrue(state.goBack())
        XCTAssertEqual(state.path.last, .userList(.followers(userID: "fixture-target")))
        XCTAssertTrue(state.goBack())
        XCTAssertTrue(state.goBack())
        XCTAssertFalse(state.goBack())
    }

    func testEmptyUserIDCannotCreateAnUnrecoverableDestination() {
        var state = MissCatProfileNavigationState()
        state.openProfile("")
        XCTAssertTrue(state.path.isEmpty)
    }

    func testProfileEditingUsesTheTypedSwiftUIDestination() {
        let profile = MissCatProfileUser(id: "fixture-self", name: "だわくん", username: "wada")
        var state = MissCatProfileNavigationState()

        state.editProfile(profile)

        XCTAssertEqual(state.path, [.editProfile(profile)])
        XCTAssertTrue(state.goBack())
        XCTAssertTrue(state.path.isEmpty)
    }

    func testBackVisibilityDependsOnRouteNestingRatherThanProfileOwnership() {
        XCTAssertFalse(
            MissCatProfileNavigationState.showsBack(
                isRoot: true,
                userID: "fixture-self",
                accountUserID: "fixture-self"
            )
        )
        XCTAssertTrue(
            MissCatProfileNavigationState.showsBack(
                isRoot: false,
                userID: "fixture-self",
                accountUserID: "fixture-self"
            )
        )
        XCTAssertTrue(
            MissCatProfileNavigationState.showsBack(
                isRoot: true,
                userID: "fixture-target",
                accountUserID: "fixture-self"
            )
        )
        XCTAssertTrue(
            MissCatProfileNavigationState.showsBack(
                isRoot: false,
                userID: "fixture-target",
                accountUserID: "fixture-self"
            )
        )
    }

    func testEveryLoginProfileFixtureRouteIsExplicitAndCredentialFree() {
        XCTAssertEqual(
            MissCatLoginProfileFixtureRoute.parse([
                "MissCat", "--login-profile-fixture", "--login-profile-auth",
                "--login-profile-auth-prepare-error"
            ]),
            .authentication(failPreparationOnce: true, failBrowserOnce: false)
        )
        XCTAssertEqual(
            MissCatLoginProfileFixtureRoute.parse([
                "MissCat", "--login-profile-fixture", "--login-profile-profile",
                "--login-profile-unfollow-error", "--login-profile-edit-error"
            ]),
            .profile(
                failUnfollowOnce: true,
                failEditOnce: true,
                startsAtSelfProfile: false,
                usesOuterShell: false
            )
        )
        XCTAssertEqual(
            MissCatLoginProfileFixtureRoute.parse([
                "MissCat", "--login-profile-fixture", "--login-profile-profile",
                "--login-profile-root-self"
            ]),
            .profile(
                failUnfollowOnce: false,
                failEditOnce: false,
                startsAtSelfProfile: true,
                usesOuterShell: false
            )
        )
        XCTAssertEqual(
            MissCatLoginProfileFixtureRoute.parse([
                "MissCat", "--login-profile-fixture", "--login-profile-profile",
                "--login-profile-ordinary-shell"
            ]),
            .profile(
                failUnfollowOnce: false,
                failEditOnce: false,
                startsAtSelfProfile: false,
                usesOuterShell: true
            )
        )
        XCTAssertNil(MissCatLoginProfileFixtureRoute.parse(["MissCat"]))
    }

    @MainActor
    func testOrdinaryRouteAccessibilityActionUsesObservableSwiftUIState() {
        let state = MissCatProfileOrdinaryActionState()

        XCTAssertEqual(state.lastAction, "none")
        state.record("settings")
        XCTAssertEqual(state.lastAction, "settings")
        XCTAssertFalse(MissCatProfileShellOwnership.outerShell.ownsNavigationStack)
        XCTAssertTrue(MissCatProfileShellOwnership.profileFamily.ownsNavigationStack)
    }
}

final class MissCatLoginProfileFixtureRepositoryTests: XCTestCase {
    private let account = MissCatProfileAccount(
        userID: "fixture-self",
        instance: "fixture.invalid",
        token: "fixture-token-not-a-secret"
    )

    func testFixtureSearchAndRelationshipListsUseOnlyDeterministicLocalModels() async throws {
        let repository = MissCatProfileFixtureRepository(
            account: account,
            failUnfollowOnce: false,
            failEditOnce: false
        )

        let search = try await repository.users(kind: .search(query: "fixture"), cursor: nil, limit: 40)
        let followers = try await repository.users(kind: .followers(userID: "fixture-target"), cursor: nil, limit: 40)
        let following = try await repository.users(kind: .following(userID: "fixture-target"), cursor: nil, limit: 40)

        XCTAssertEqual(search.items.map(\.id), ["fixture-target", "fixture-self", "fixture-friend"])
        XCTAssertEqual(followers.items.map(\.id), ["fixture-friend", "fixture-self"])
        XCTAssertEqual(following.items.map(\.id), ["fixture-self", "fixture-friend"])
        XCTAssertTrue(search.items.allSatisfy { $0.avatarURL?.scheme == "misscat-fixture" })
    }

    func testFixtureFollowFailureIsOneShotAndDoesNotMutateConfirmedState() async throws {
        let repository = MissCatProfileFixtureRepository(
            account: account,
            failUnfollowOnce: true,
            failEditOnce: false
        )

        try await repository.setFollowing(true, userID: "fixture-target")
        let afterFollow = try await repository.relationship(userID: "fixture-target")
        XCTAssertTrue(afterFollow)
        do {
            try await repository.setFollowing(false, userID: "fixture-target")
            XCTFail("The configured first unfollow must fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "フォロー状態を更新できませんでした")
        }
        let afterFailedUnfollow = try await repository.relationship(userID: "fixture-target")
        XCTAssertTrue(afterFailedUnfollow)
        try await repository.setFollowing(false, userID: "fixture-target")
        let afterUnfollow = try await repository.relationship(userID: "fixture-target")
        XCTAssertFalse(afterUnfollow)
    }

    func testFixtureEditFailureRetainsServerStateThenRetryAppliesTextAndImages() async throws {
        let repository = MissCatProfileFixtureRepository(
            account: account,
            failUnfollowOnce: false,
            failEditOnce: true
        )
        let before = try await repository.profile(userID: account.userID)
        let patch = MissCatProfileUpdatePatch(
            name: "更新後",
            description: "保存済み",
            avatarImage: .remove,
            bannerImage: .remove
        )

        do {
            _ = try await repository.updateProfile(patch: patch)
            XCTFail("The configured first update must fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "プロフィールを保存できませんでした")
        }
        let afterFailedUpdate = try await repository.profile(userID: account.userID)
        XCTAssertEqual(afterFailedUpdate, before)

        let after = try await repository.updateProfile(patch: patch)
        XCTAssertEqual(after.name, "更新後")
        XCTAssertEqual(after.description, "保存済み")
        XCTAssertNil(after.avatarURL)
        XCTAssertNil(after.bannerURL)
    }
}
