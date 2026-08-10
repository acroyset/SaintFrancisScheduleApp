//
//  LocalGradeStore.swift
//  Schedule
//

import Foundation
import SwiftUI

struct LocalClassGradeRecord: Codable {
    var gpaPercentage: String = ""
    var gpaType: String = "Normal"
    var finalExamWeight: String = "15"
    var desiredFinalGrade: String = "A"
    var hypotheticalScore: String = "100"
    var categoryScenario: String = "Single Assignment Category"
    var categoryGrade: String = "88"
    var categoryWeight: String = "30"
    var assignmentWeightInCategory: String = "20"

    var hasLegacyNinetyFiveGPA: Bool {
        gpaPercentage.trimmingCharacters(in: .whitespacesAndNewlines) == "95"
    }
}

final class LocalGradeStore: ObservableObject {
    static let shared = LocalGradeStore()

    @Published private var records: [Int: LocalClassGradeRecord] = [:]
    @Published private(set) var pendingLegacyNinetyFiveReviewIndices: Set<Int> = []

    private let defaultsKey = "LocalGradeStore.records.v1"
    private let legacyReviewInitializedKey = "LocalGradeStore.didInitializeNinetyFiveReview.v4"
    private let legacyReviewIndicesKey = "LocalGradeStore.pendingNinetyFiveReviewIndices.v4"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func record(for index: Int, className: String) -> LocalClassGradeRecord {
        let record = records[index] ?? LocalClassGradeRecord()
        if record.gpaType.isEmpty {
            var updated = record
            updated.gpaType = inferClassLevel(from: className)
            return updated
        }
        return record
    }

    func seedClassTypes(from data: ScheduleData) {
        var didChange = false

        for index in 0..<min(7, data.classes.count) {
            let className = data.classes[index].name
            let inferredType = inferClassLevel(from: className)
            let existing = records[index] ?? LocalClassGradeRecord(gpaType: inferredType)

            if records[index] == nil {
                objectWillChange.send()
                records[index] = existing
                didChange = true
                continue
            }

            if existing.gpaType.isEmpty {
                var updated = existing
                updated.gpaType = inferredType
                objectWillChange.send()
                records[index] = updated
                didChange = true
            }
        }

        if didChange {
            save()
        }
    }

    func binding(
        for index: Int,
        className: String,
        keyPath: WritableKeyPath<LocalClassGradeRecord, String>
    ) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.record(for: index, className: className)[keyPath: keyPath] ?? ""
            },
            set: { [weak self] newValue in
                self?.updateRecord(for: index, className: className) { record in
                    record[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func needsLegacyNinetyFiveReview(for index: Int, className: String? = nil) -> Bool {
        if let className,
           className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        return pendingLegacyNinetyFiveReviewIndices.contains(index)
            && records[index]?.hasLegacyNinetyFiveGPA == true
    }

    func resolveLegacyNinetyFiveReview(
        for index: Int,
        keepGrade: Bool
    ) {
        resolveLegacyNinetyFiveReviews(for: [index], keepGrades: keepGrade)
    }

    func resolveLegacyNinetyFiveReviews(
        for indices: [Int],
        keepGrades: Bool
    ) {
        let reviewedIndices = Set(indices).intersection(pendingLegacyNinetyFiveReviewIndices)
        guard !reviewedIndices.isEmpty else { return }

        objectWillChange.send()
        if !keepGrades {
            for index in reviewedIndices {
                guard var updated = records[index], updated.hasLegacyNinetyFiveGPA else { continue }
                updated.gpaPercentage = ""
                records[index] = updated
            }
            save()
        }

        pendingLegacyNinetyFiveReviewIndices.subtract(reviewedIndices)
        savePendingLegacyReviews()
    }

    private func updateRecord(
        for index: Int,
        className: String,
        mutate: (inout LocalClassGradeRecord) -> Void
    ) {
        var updated = record(for: index, className: className)
        mutate(&updated)
        objectWillChange.send()
        records[index] = updated
        if pendingLegacyNinetyFiveReviewIndices.contains(index),
           !updated.hasLegacyNinetyFiveGPA {
            pendingLegacyNinetyFiveReviewIndices.remove(index)
            savePendingLegacyReviews()
        }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Int: LocalClassGradeRecord].self, from: data) else {
            initializeLegacyNinetyFiveReviewIfNeeded()
            return
        }

        records = decoded
        initializeLegacyNinetyFiveReviewIfNeeded()
    }

    private func initializeLegacyNinetyFiveReviewIfNeeded() {
        if defaults.bool(forKey: legacyReviewInitializedKey) {
            let savedIndices = defaults.array(forKey: legacyReviewIndicesKey) as? [Int] ?? []
            pendingLegacyNinetyFiveReviewIndices = Set(savedIndices).filter {
                records[$0]?.hasLegacyNinetyFiveGPA == true
            }
            savePendingLegacyReviews()
            return
        }

        pendingLegacyNinetyFiveReviewIndices = Set(
            records.compactMap { index, record in
                record.hasLegacyNinetyFiveGPA ? index : nil
            }
        )
        defaults.set(true, forKey: legacyReviewInitializedKey)
        savePendingLegacyReviews()
    }

    private func savePendingLegacyReviews() {
        defaults.set(
            pendingLegacyNinetyFiveReviewIndices.sorted(),
            forKey: legacyReviewIndicesKey
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
