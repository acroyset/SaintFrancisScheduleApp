import XCTest
import SwiftUI
@testable import Schedule

final class RegressionFixesTests: XCTestCase {
    func testClassJSONRoundTripPreservesStableID() throws {
        let id = UUID(uuidString: "F33B359A-8FB7-44ED-9DD0-0A691C2E6B9D")!
        let original = ClassItem(id: id, name: "Math", teacher: "Ms. Rivera", room: "204")
        let data = try JSONEncoder().encode(original)
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))

        let decoded = ScheduleParsing.parseClass(line)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, id)
    }

    func testLegacyClassDecodeIsMarkedForIDMigration() throws {
        let legacy = Data(#"{"name":"Math","teacher":"Ms. Rivera","room":"204"}"#.utf8)

        let decoded = try JSONDecoder().decode(ClassItem.self, from: legacy)

        XCTAssertTrue(decoded.needsIDMigration)
        let migratedRoundTrip = try JSONDecoder().decode(
            ClassItem.self,
            from: JSONEncoder().encode(decoded)
        )
        XCTAssertFalse(migratedRoundTrip.needsIDMigration)
        XCTAssertEqual(migratedRoundTrip.id, decoded.id)
    }

    @MainActor
    func testLegacyHomeworkFollowsClassRenameAfterMigration() throws {
        let suiteName = "RegressionFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyHomework = HomeworkItem(
            className: "Period 1",
            title: "Read chapter 3",
            details: "",
            dueDate: Date(),
            priority: .normal,
            reminderChoice: .none,
            isComplete: false,
            createdAt: Date()
        )
        defaults.set(try JSONEncoder().encode([legacyHomework]), forKey: "HomeworkItems")

        let classID = UUID()
        let store = HomeworkStore(defaults: defaults, syncSideEffects: false)
        XCTAssertTrue(
            store.reconcileClassReferences(
                with: [ClassItem(id: classID, name: "Period 1", teacher: "", room: "")]
            )
        )

        let renamedClass = ClassItem(id: classID, name: "Math", teacher: "", room: "")
        XCTAssertTrue(store.reconcileClassReferences(with: [renamedClass]))

        let migrated = try XCTUnwrap(store.items(forClass: renamedClass).first)
        XCTAssertEqual(migrated.classID, classID)
        XCTAssertEqual(migrated.className, "Math")
    }

    func testPlaceholderClassesNormalizeToEmptyFields() {
        let input = ScheduleData(
            classes: [ClassItem(name: "Period 1", teacher: "Teacher", room: "Room")],
            days: []
        )

        let normalized = input.normalized()

        XCTAssertEqual(normalized.classes[0].name, "")
        XCTAssertEqual(normalized.classes[0].teacher, "")
        XCTAssertEqual(normalized.classes[0].room, "")
    }

    func testNewGradeRecordStartsBlank() {
        XCTAssertEqual(LocalClassGradeRecord().gpaPercentage, "")
    }

    func testGraphitePrimaryColorIsDetectedAsLight() {
        XCTAssertGreaterThan(Color(hex: "#D1D1D6FF").luminance(), 0.5)
    }

    func testGraphiteForegroundIsAdjustedForLightModeContrast() {
        let background = Color.white
        let readableGraphite = Color(hex: "#D1D1D6FF")
            .accessibleForegroundColor(against: background)

        XCTAssertGreaterThanOrEqual(
            readableGraphite.contrastRatio(with: background),
            4.5
        )
    }

    func testThemePresetMatchingFindsOceanAfterReset() {
        XCTAssertEqual(
            ThemePreset.matching(
                primaryHex: "#00A5FFFF",
                secondaryHex: "#00A5FF19",
                tertiaryHex: "#FFFFFFFF"
            )?.id,
            "ocean"
        )
    }

    func testLandscapeAddSelectorDoesNotInheritToolbarWidth() {
        XCTAssertNil(
            HomeLayoutMetrics.addSelectorWidth(
                isPortrait: false,
                toolbarWidth: 1_024
            )
        )
        XCTAssertEqual(
            HomeLayoutMetrics.addSelectorWidth(
                isPortrait: true,
                toolbarWidth: 390
            ),
            390
        )
    }

    func testCourseJSONUsesCorrectRequirementsKey() throws {
        let course = Course(
            id: "math_test",
            name: "Test Math",
            requirements: ["Algebra 1"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        )

        let encoded = try JSONEncoder().encode(course)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(json["requirements"] as? [String], ["Algebra 1"])
        XCTAssertEqual(
            try JSONDecoder().decode(Course.self, from: encoded).requirements,
            ["Algebra 1"]
        )
    }

    func testCourseCatalogUsesCorrectPlacementAndSophomoreSpelling() {
        let requirements = loadSFHSCourses().flatMap(\.requirements)

        XCTAssertTrue(requirements.contains("HSPT Placement Test Scores"))
        XCTAssertEqual(requirements.filter { $0 == "Current Sophomore" }.count, 2)
        XCTAssertFalse(requirements.contains { $0.contains("Placment") })
        XCTAssertFalse(requirements.contains { $0.contains("Sophmore") })
    }

    @MainActor
    func testV4RequiresAnExplicitChoiceBeforeChangingLegacyNinetyFive() throws {
        let suiteName = "RegressionFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyRecord = LocalClassGradeRecord(
            gpaPercentage: "95",
            gpaType: "Honors",
            desiredFinalGrade: "B"
        )
        let legitimateRecord = LocalClassGradeRecord(gpaPercentage: "95")
        defaults.set(
            try JSONEncoder().encode([0: legacyRecord, 1: legitimateRecord]),
            forKey: "LocalGradeStore.records.v1"
        )
        defaults.set(
            true,
            forKey: "LocalGradeStore.didClearLegacyNinetyFiveDefaults.v2"
        )

        let migratedStore = LocalGradeStore(defaults: defaults)
        XCTAssertEqual(
            migratedStore.record(for: 0, className: "Chemistry").gpaPercentage,
            "95"
        )
        XCTAssertEqual(
            migratedStore.record(for: 0, className: "Chemistry").desiredFinalGrade,
            "B"
        )
        XCTAssertTrue(migratedStore.needsLegacyNinetyFiveReview(for: 0))
        XCTAssertTrue(migratedStore.needsLegacyNinetyFiveReview(for: 1))

        migratedStore.resolveLegacyNinetyFiveReview(
            for: 0,
            keepGrade: false
        )
        migratedStore.resolveLegacyNinetyFiveReview(
            for: 1,
            keepGrade: true
        )

        let reviewedStore = LocalGradeStore(defaults: defaults)
        XCTAssertEqual(reviewedStore.record(for: 0, className: "Chemistry").gpaPercentage, "")
        XCTAssertEqual(reviewedStore.record(for: 1, className: "English").gpaPercentage, "95")
        XCTAssertFalse(reviewedStore.needsLegacyNinetyFiveReview(for: 0))
        XCTAssertFalse(reviewedStore.needsLegacyNinetyFiveReview(for: 1))

        reviewedStore.binding(
            for: 0,
            className: "Chemistry",
            keyPath: \.gpaPercentage
        ).wrappedValue = "95"

        let reloadedStore = LocalGradeStore(defaults: defaults)
        XCTAssertEqual(
            reloadedStore.record(for: 0, className: "Chemistry").gpaPercentage,
            "95"
        )
        XCTAssertFalse(reloadedStore.needsLegacyNinetyFiveReview(for: 0))
    }

    @MainActor
    func testLegacyNinetyFiveBulkReviewIgnoresPlaceholderClasses() throws {
        let suiteName = "RegressionFixesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let records = [
            0: LocalClassGradeRecord(gpaPercentage: "95"),
            1: LocalClassGradeRecord(gpaPercentage: "95")
        ]
        defaults.set(
            try JSONEncoder().encode(records),
            forKey: "LocalGradeStore.records.v1"
        )

        let store = LocalGradeStore(defaults: defaults)
        XCTAssertFalse(store.needsLegacyNinetyFiveReview(for: 0, className: ""))
        XCTAssertTrue(store.needsLegacyNinetyFiveReview(for: 0, className: "Chemistry"))

        store.resolveLegacyNinetyFiveReviews(for: [0, 1], keepGrades: false)

        XCTAssertEqual(store.record(for: 0, className: "Chemistry").gpaPercentage, "")
        XCTAssertEqual(store.record(for: 1, className: "English").gpaPercentage, "")
        XCTAssertFalse(store.needsLegacyNinetyFiveReview(for: 0))
        XCTAssertFalse(store.needsLegacyNinetyFiveReview(for: 1))
    }

    func testDefaultMapIgnoresAdvisoryAndHomeroom() {
        XCTAssertEqual(
            CampusMapData.unplacedAcademicClassCount(in: ScheduleData.defaultClasses),
            0
        )

        var classes = ScheduleData.defaultClasses
        classes[0] = ClassItem(name: "Chemistry", teacher: "Dr. Stone", room: "")
        XCTAssertEqual(CampusMapData.unplacedAcademicClassCount(in: classes), 1)
    }

    func testWhitespaceOnlyAnnouncementsAreRejected() {
        XCTAssertThrowsError(
            try DailyAnnouncementsService.validatedAnnouncementHTML(" \n\t ")
        )
    }

    func testAthleticsRemoteTyposAreSanitized() {
        XCTAssertEqual(
            AthleticsTextSanitizer.sanitize("CCS SemiFinal at Aqautic Center"),
            "CCS Semifinal at Aquatic Center"
        )
        XCTAssertEqual(
            AthleticsTextSanitizer.sanitize("Santa Clara, Ca -  Wilcox HS"),
            "Santa Clara, CA - Wilcox HS"
        )
    }

    func testRefreshStatusIsHiddenBehindCreationSurfaces() {
        XCTAssertTrue(
            ContentOverlayVisibility.showsCompactRefreshStatus(
                retryAttempt: 1,
                hasCachedSchedule: true,
                isCreationSheetPresented: false,
                isAddSelectorExpanded: false
            )
        )
        XCTAssertFalse(
            ContentOverlayVisibility.showsCompactRefreshStatus(
                retryAttempt: 1,
                hasCachedSchedule: true,
                isCreationSheetPresented: true,
                isAddSelectorExpanded: false
            )
        )
        XCTAssertFalse(
            ContentOverlayVisibility.showsCompactRefreshStatus(
                retryAttempt: 1,
                hasCachedSchedule: true,
                isCreationSheetPresented: false,
                isAddSelectorExpanded: true
            )
        )
    }

    func testRefreshFailureIsHiddenBehindCreationSurfaces() {
        XCTAssertTrue(
            ContentOverlayVisibility.showsScheduleLoadError(
                hasCachedSchedule: true,
                isCreationSheetPresented: false,
                isAddSelectorExpanded: false
            )
        )
        XCTAssertFalse(
            ContentOverlayVisibility.showsScheduleLoadError(
                hasCachedSchedule: true,
                isCreationSheetPresented: true,
                isAddSelectorExpanded: false
            )
        )
        XCTAssertFalse(
            ContentOverlayVisibility.showsScheduleLoadError(
                hasCachedSchedule: true,
                isCreationSheetPresented: false,
                isAddSelectorExpanded: true
            )
        )
        XCTAssertTrue(
            ContentOverlayVisibility.showsScheduleLoadError(
                hasCachedSchedule: false,
                isCreationSheetPresented: false,
                isAddSelectorExpanded: true
            )
        )
    }

    func testReminderSavedWithoutNotificationsCanBeSavedAgain() {
        XCTAssertTrue(
            ReminderFormValidation.canSave(
                title: "Bring permission slip",
                hasSelectedOffsets: false,
                wasSavedWithoutNotifications: true,
                isRequestingAuthorization: false
            )
        )
        XCTAssertFalse(
            ReminderFormValidation.canSave(
                title: "Bring permission slip",
                hasSelectedOffsets: false,
                wasSavedWithoutNotifications: false,
                isRequestingAuthorization: false
            )
        )
    }

    @MainActor
    func testLightweightProgressRefreshUpdatesCurrentClass() {
        let lines = [
            ScheduleLine(content: "", base: "$1", className: "Math", startSec: 100, endSec: 200),
            ScheduleLine(content: "", base: "$2", className: "English", startSec: 300, endSec: 400)
        ]

        let refreshed = ScheduleRenderer.shared.refreshingProgress(
            in: lines,
            selectedDate: Date(),
            nowSeconds: 150
        )

        XCTAssertTrue(refreshed[0].isCurrentClass)
        XCTAssertEqual(refreshed[0].progress, 0.5)
        XCTAssertFalse(refreshed[1].isCurrentClass)
    }
}
