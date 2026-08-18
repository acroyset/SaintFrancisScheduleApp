import XCTest
import SwiftUI
@testable import Schedule

final class RegressionFixesTests: XCTestCase {
    func testSpecialScheduleCodeUsesDaysFileFormat() throws {
        let code = """
        Welcome Home - 9:15 - 9:45
        $2 - 9:55 - 10:05
        $4 - 10:10 - 10:20
        $6 - 10:25 - 10:35
        $1 - 10:40 - 10:50
        $3 - 10:55 - 11:05
        $5 - 11:10 - 11:20
        $7 - 11:25 - 11:35
        $end
        """
        let special = try XCTUnwrap(
            SpecialSchedule(code: code)
        )

        XCTAssertEqual(special.day.name, "Special")
        XCTAssertEqual(
            special.day.names,
            ["Welcome Home", "$2", "$4", "$6", "$1", "$3", "$5", "$7"]
        )
        XCTAssertEqual(special.day.startTimes.first?.string(), "9:15")
        XCTAssertEqual(special.day.endTimes.last?.string(), "11:35")
    }

    func testSpecialScheduleRejectsMalformedCode() {
        XCTAssertNil(SpecialSchedule(code: "$2 - nope - 9:00"))
        XCTAssertNil(SpecialSchedule(code: "$2 - 9:00 - 8:15"))
    }

    @MainActor
    func testOrdinarySpecialDayKeepsFallbackActivity() {
        let data = ScheduleData(
            classes: ScheduleData.defaultClasses,
            days: Array(repeating: Day(), count: 10) + [
                Day(
                    name: "Special",
                    names: ["$14"],
                    startTimes: [Time("8:00")],
                    endTimes: [Time("2:30")]
                )
            ]
        )

        let lines = ScheduleRenderer.shared.render(
            dayCode: "s1",
            selectedDate: Date(timeIntervalSince1970: 0),
            data: data,
            events: [],
            specialScheduleCode: ""
        )

        XCTAssertEqual(lines.map(\.className), ["Activity"])
        XCTAssertEqual(lines.map(\.timeRange), ["8:00 to 2:30"])
    }

    @MainActor
    func testSpecialScheduleResolverUsesSheetCodeAndKeepsNote() {
        let selectedDate = Date(timeIntervalSince1970: 0)
        let key = ScheduleSelectionResolver.scheduleKey(for: selectedDate)
        let classes = (1...7).map {
            ClassItem(name: "Class \($0)", teacher: "Teacher \($0)", room: "Room \($0)")
        }
        let fallbackSpecialDay = Day(
            name: "Special",
            names: ["$14"],
            startTimes: [Time("8:00")],
            endTimes: [Time("2:30")]
        )
        let data = ScheduleData(
            classes: classes,
            days: Array(repeating: Day(), count: 10) + [fallbackSpecialDay]
        ).normalized()

        let resolved = ScheduleSelectionResolver.resolve(
            selectedDate: selectedDate,
            scheduleDict: [
                key: [
                    "s1",
                    "First Day of School",
                    """
                    $2 - 8:15 - 9:00
                    $4 - 9:07 - 9:52
                    $11 - 9:52 - 10:12
                    $6 - 10:12 - 10:57
                    $1 - 11:04 - 11:49
                    $8 - 11:49 - 12:30
                    $3 - 12:30 - 1:15
                    $5 - 1:22 - 2:07
                    $7 - 2:15 - 3:00
                    """
                ]
            ],
            data: data,
            events: []
        )

        XCTAssertEqual(resolved.note, "First Day of School")
        XCTAssertEqual(
            resolved.scheduleLines.map(\.base),
            ["$2", "$4", "$11", "$6", "$1", "$8", "$3", "$5", "$7"]
        )
    }

    func testScheduleCSVReadsMultilineSpecialCodeColumnByHeader() throws {
        let csv = """
        ,Day,Note,Date,Special Day Code
        08-13-26,s1,First Day of School,8-13-26,"Welcome Home - 9:15 - 9:45
        $2 - 9:55 - 10:05"
        08-14-26,g1,Regular day,8-14-26,
        """

        let schedule = try XCTUnwrap(CSVParser.parseScheduleCSV(csv))

        XCTAssertEqual(schedule["08-13-26"]?[0], "s1")
        XCTAssertEqual(schedule["08-13-26"]?[1], "First Day of School")
        XCTAssertEqual(
            schedule["08-13-26"]?[2],
            "Welcome Home - 9:15 - 9:45\n$2 - 9:55 - 10:05"
        )
        XCTAssertEqual(schedule["08-14-26"]?[2], "")
    }

    func testScheduleCSVUsesFifthColumnOnlyForSpecialDays() throws {
        let csv = """
        ,Day,Note,Date,Anything
        08-13-26,s1,First Day of School,8-13-26,"$2 - 9:55 - 10:05"
        08-14-26,g1,Regular day,8-14-26,"$3 - 10:10 - 10:20"
        """

        let schedule = try XCTUnwrap(CSVParser.parseScheduleCSV(csv))

        XCTAssertEqual(schedule["08-13-26"]?[2], "$2 - 9:55 - 10:05")
        XCTAssertEqual(schedule["08-14-26"]?[2], "")
    }

    func testLightweightSpecialCodeCSVReadsMultilineColumnE() throws {
        let csv = """
        "","Special Day Code"
        "08-13-26","Welcome Home - 9:15 - 9:45
        $2 - 9:55 - 10:05
        $end"
        """

        XCTAssertEqual(
            CSVParser.parseSpecialCodeCSV(csv, dateKey: "08-13-26"),
            "Welcome Home - 9:15 - 9:45\n$2 - 9:55 - 10:05\n$end"
        )
    }

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

    func testAllMapLayerOnlyShowsRoomsWithClasses() {
        let locations = CampusMapData.locations(for: [
            ClassItem(name: "English", teacher: "Ms. Lee", room: "402"),
            ClassItem(name: "Physics", teacher: "Dr. Stone", room: "Room 521")
        ])

        let markers = CampusMapData.roomMarkers(
            for: .all,
            classLocations: locations
        )

        XCTAssertEqual(Set(markers.map(\.room)), ["402", "521"])
    }

    func testFloorMapLayerStillShowsEveryRoomOnThatFloor() {
        let markers = CampusMapData.roomMarkers(
            for: .first,
            classLocations: []
        )

        XCTAssertFalse(markers.isEmpty)
        XCTAssertTrue(markers.allSatisfy { $0.layer == .first })
        XCTAssertTrue(markers.contains { $0.room == "402" })
    }

    func testMapCalloutLayoutSeparatesClusteredClassTitles() throws {
        let items = (0..<7).map { index in
            MapCalloutLayoutItem(
                id: "room-\(index)",
                anchor: CGPoint(
                    x: 300 + CGFloat(index % 3) * 8,
                    y: 260 + CGFloat(index / 3) * 8
                ),
                preferredHorizontalDirection: 1,
                preferredVerticalDirection: 1
            )
        }
        let cardSize = CGSize(width: 190, height: 36)
        let bounds = CGRect(x: 0, y: 0, width: 1_400, height: 1_100)
        let offsets = MapCalloutLayoutEngine.offsets(
            for: items,
            cardSize: cardSize,
            connectorLength: 28,
            bounds: bounds
        )

        XCTAssertEqual(offsets.count, items.count)

        let titleRects = try items.map { item -> CGRect in
            let offset = try XCTUnwrap(offsets[item.id])
            return CGRect(
                x: item.anchor.x + offset.width - cardSize.width / 2,
                y: item.anchor.y + offset.height - cardSize.height / 2,
                width: cardSize.width,
                height: cardSize.height
            )
        }

        for (index, titleRect) in titleRects.enumerated() {
            XCTAssertTrue(bounds.contains(titleRect))
            for otherRect in titleRects.dropFirst(index + 1) {
                XCTAssertFalse(
                    titleRect.insetBy(dx: -4.5, dy: -4.5).intersects(
                        otherRect.insetBy(dx: -4.5, dy: -4.5)
                    )
                )
            }
        }

        XCTAssertEqual(
            offsets,
            MapCalloutLayoutEngine.offsets(
                for: Array(items.reversed()),
                cardSize: cardSize,
                connectorLength: 28,
                bounds: bounds
            )
        )
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
