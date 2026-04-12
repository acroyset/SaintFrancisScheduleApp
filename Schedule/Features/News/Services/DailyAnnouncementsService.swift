//
//  DailyAnnouncementsService.swift
//  Schedule
//

import Foundation

struct DailyAnnouncementsService {
    private let spreadsheetID = "1-Tz6jAzcu-dPW3a0J5H7dqSc-8ZzgVDVNH9ABAUvmu0"
    private let gid = "0"
    private let maxAttempts = 3

    func fetchHTML() async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }

                let csv = decodeCSV(from: data)
                guard let firstField = parseFirstCSVField(csv) else {
                    throw URLError(.cannotParseResponse)
                }

                return firstField.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                lastError = error

                if attempt < maxAttempts - 1 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }

        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private var csvURL: URL {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv&gid=\(gid)")!
    }

    private var request: URLRequest {
        var request = URLRequest(url: csvURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func decodeCSV(from data: Data) -> String {
        let candidates: [String.Encoding] = [.utf8, .utf16, .unicode, .isoLatin1]

        for encoding in candidates {
            if let value = String(data: data, encoding: encoding) {
                return value.replacingOccurrences(of: "\u{feff}", with: "")
            }
        }

        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{feff}", with: "")
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
