//
//  SheetStore.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI
import Foundation

import SwiftUI
import WebKit

@MainActor
final class SheetStore: ObservableObject {
    
    @Published var lastUpdatedString: String = "—"
    @Published var htmlContent: String = ""

    private let spreadsheetID = "1-Tz6jAzcu-dPW3a0J5H7dqSc-8ZzgVDVNH9ABAUvmu0"
    private let gid = "0"

    private var pollTask: Task<Void, Never>?
    private let refreshSeconds: UInt64 = 30

    func startPolling() async {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchFromCSV()
                try? await Task.sleep(nanoseconds: refreshSeconds * 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func csvURL() -> URL {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv&gid=\(gid)")!
    }

    private func updateTimestamp() {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        lastUpdatedString = f.string(from: Date())
    }

    private func fetchFromCSV() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: csvURL())
            guard let csv = String(data: data, encoding: .utf8) else {
                htmlContent = "<p>No CSV data</p>"
                return
            }
            updateTimestamp()
            
            guard let firstField = parseFirstCSVField(csv) else {
                htmlContent = "<p>No news content found</p>"
                return
            }

            htmlContent = firstField.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            htmlContent = "<p>Error loading: \(error)</p>"
        }
    }

    private func parseFirstCSVField(_ csv: String) -> String? {
        var field = ""
        var index = csv.startIndex
        var insideQuotes = false

        while index < csv.endIndex {
            let character = csv[index]

            if character == "\"" {
                let nextIndex = csv.index(after: index)
                if insideQuotes, nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                    field.append("\"")
                    index = csv.index(after: nextIndex)
                    continue
                }

                insideQuotes.toggle()
                index = nextIndex
                continue
            }

            if !insideQuotes && (character == "," || character == "\n" || character == "\r") {
                break
            }

            field.append(character)
            index = csv.index(after: index)
        }

        return field.isEmpty ? nil : field
    }
}
