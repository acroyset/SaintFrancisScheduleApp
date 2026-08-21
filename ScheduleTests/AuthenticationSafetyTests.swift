import XCTest
@testable import Schedule

final class AuthenticationSafetyTests: XCTestCase {
    @MainActor
    func testAccountDeletionAllowsOnlyOneMatchingIdentity() {
        XCTAssertNoThrow(
            try AuthenticationManager.validateAccountDeletionIdentity(
                targetUserID: "user-a",
                reauthenticatedUserID: "user-a",
                currentFirebaseUserID: "user-a"
            )
        )
    }

    @MainActor
    func testAccountDeletionRejectsMissingOrMismatchedIdentities() {
        let invalidIdentities: [(target: String?, reauthenticated: String, current: String?)] = [
            (nil, "user-a", "user-a"),
            ("user-a", "user-b", "user-a"),
            ("user-a", "user-a", "user-b"),
            ("user-a", "user-a", nil)
        ]

        for identity in invalidIdentities {
            XCTAssertThrowsError(
                try AuthenticationManager.validateAccountDeletionIdentity(
                    targetUserID: identity.target,
                    reauthenticatedUserID: identity.reauthenticated,
                    currentFirebaseUserID: identity.current
                )
            ) { error in
                XCTAssertTrue(error is AuthenticationManager.AccountDeletionIdentityError)
            }
        }
    }

    func testAccountReauthenticationMethodUsesLinkedProvider() {
        XCTAssertEqual(
            AccountReauthenticationMethod(providerIDs: ["password"]),
            .password
        )
        XCTAssertEqual(
            AccountReauthenticationMethod(providerIDs: ["google.com"]),
            .google
        )
        XCTAssertEqual(
            AccountReauthenticationMethod(providerIDs: ["apple.com"]),
            .apple
        )
    }

    func testAppleReauthenticationWinsForAppleLinkedAccount() {
        XCTAssertEqual(
            AccountReauthenticationMethod(
                providerIDs: ["password", "google.com", "apple.com"]
            ),
            .apple
        )
    }

    @MainActor
    func testSignOutPreservesLocalClassesFileAndResetsSession() throws {
        let suiteName = "AuthenticationSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let classesURL = try classesDocumentsURL()
        let originalClasses = try? Data(contentsOf: classesURL)
        let sentinelClasses = Data("unsynced local classes".utf8)
        try sentinelClasses.write(to: classesURL, options: .atomic)
        defer {
            if let originalClasses {
                try? originalClasses.write(to: classesURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: classesURL)
            }
        }

        defaults.set(true, forKey: "HasCompletedOnboarding")
        defaults.set(true, forKey: "HasLaunchedBefore")
        defaults.set("1.17", forKey: "LastSeenVersion")

        var firebaseSignedOut = false
        var googleSignedOut = false
        let manager = AuthenticationManager(
            startAuthStateListener: false,
            firebaseSignOut: { firebaseSignedOut = true },
            googleSignOut: { googleSignedOut = true },
            userDefaults: defaults
        )
        manager.user = User(id: "user-a", email: "user@example.com")

        manager.signOut()

        XCTAssertTrue(firebaseSignedOut)
        XCTAssertTrue(googleSignedOut)
        XCTAssertNil(manager.user)
        XCTAssertFalse(defaults.bool(forKey: "HasCompletedOnboarding"))
        XCTAssertFalse(defaults.bool(forKey: "HasLaunchedBefore"))
        XCTAssertNil(defaults.object(forKey: "LastSeenVersion"))
        XCTAssertEqual(try Data(contentsOf: classesURL), sentinelClasses)
    }
}
