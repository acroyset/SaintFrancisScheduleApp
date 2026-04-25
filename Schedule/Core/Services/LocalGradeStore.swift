//
//  LocalGradeStore.swift
//  Schedule
//

import Foundation
import SwiftUI

struct LocalClassGradeRecord: Codable {
    var gpaPercentage: String = "95"
    var gpaType: String = "Normal"
    var finalExamWeight: String = "15"
    var desiredFinalGrade: String = "A"
    var hypotheticalScore: String = "100"
    var categoryScenario: String = "Single Assignment Category"
    var categoryGrade: String = "88"
    var categoryWeight: String = "30"
    var assignmentWeightInCategory: String = "20"
}

final class LocalGradeStore: ObservableObject {
    static let shared = LocalGradeStore()

    @Published private var records: [Int: LocalClassGradeRecord] = [:]

    private let defaultsKey = "LocalGradeStore.records.v1"
    private let defaults = UserDefaults.standard

    private init() {
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

    private func updateRecord(
        for index: Int,
        className: String,
        mutate: (inout LocalClassGradeRecord) -> Void
    ) {
        var updated = record(for: index, className: className)
        mutate(&updated)
        objectWillChange.send()
        records[index] = updated
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Int: LocalClassGradeRecord].self, from: data) else {
            return
        }

        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
