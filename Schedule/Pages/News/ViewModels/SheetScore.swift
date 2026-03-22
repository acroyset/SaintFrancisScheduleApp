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
            
            // Parse CSV properly to handle newlines inside quoted cells
            var rows: [String] = []
            var currentRow = ""
            var insideQuotes = false
            var i = csv.startIndex
            
            while i < csv.endIndex {
                let char = csv[i]
                
                if char == "\"" {
                    insideQuotes = !insideQuotes
                } else if char == "\n" && !insideQuotes {
                    rows.append(currentRow)
                    currentRow = ""
                    i = csv.index(after: i)
                    continue
                } else {
                    currentRow.append(char)
                }
                
                i = csv.index(after: i)
            }
            
            if !currentRow.isEmpty {
                rows.append(currentRow)
            }
            
            guard rows.count >= 1 else {
                htmlContent = "<p>Found \(rows.count) rows</p>"
                return
            }
            
            // Get the second row (first data row after header) - A1 content
            var html = rows[0].trimmingCharacters(in: .whitespaces)
            
            // Remove surrounding quotes
            if html.hasPrefix("\"") {
                html = String(html.dropFirst())
            }
            if html.hasSuffix("\"") {
                html = String(html.dropLast())
            }
            
            // Unescape double quotes
            html = html.replacingOccurrences(of: "\"\"", with: "\"")
            
            htmlContent = html
        } catch {
            htmlContent = "<p>Error loading: \(error)</p>"
        }
    }
}
