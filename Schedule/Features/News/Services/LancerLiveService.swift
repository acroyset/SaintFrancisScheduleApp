//
//  LancerLiveService.swift
//  Schedule
//

import Foundation

struct LancerLiveService {
    private let handleURL = URL(string: "https://www.youtube.com/@sflancerlive/videos")!

    func fetchLatestVideo() async throws -> LancerLiveVideo {
        let channelID = try await resolveChannelID()
        let feedURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        let xml = String(decoding: data, as: UTF8.self)

        guard let video = parseLatestVideo(from: xml) else {
            throw URLError(.badServerResponse)
        }

        return video
    }

    private func resolveChannelID() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: handleURL)
        let html = String(decoding: data, as: UTF8.self)

        let patterns = [
            #""channelId":"(UC[^"]+)""#,
            #"https:\/\/www\.youtube\.com\/channel\/(UC[^"\/?]+)"#,
            #"channel\/(UC[\w-]+)"#
        ]

        for pattern in patterns {
            if let value = firstMatch(in: html, pattern: pattern) {
                return value
            }
        }

        throw URLError(.badServerResponse)
    }

    private func parseLatestVideo(from xml: String) -> LancerLiveVideo? {
        guard let entry = firstMatch(in: xml, pattern: #"(?s)<entry>(.*?)</entry>"#) else {
            return nil
        }

        guard
            let title = firstMatch(in: entry, pattern: #"<title>(.*?)</title>"#),
            let videoID = firstMatch(in: entry, pattern: #"<yt:videoId>(.*?)</yt:videoId>"#),
            let urlString = firstMatch(in: entry, pattern: #"<link rel=\"alternate\" href=\"(.*?)\"\s*/>"#),
            let thumbnailString = firstMatch(in: entry, pattern: #"<media:thumbnail url=\"(.*?)\""#),
            let watchURL = URL(string: decodeXMLEntities(urlString)),
            let thumbnailURL = URL(string: decodeXMLEntities(thumbnailString))
        else {
            return nil
        }

        let publishedRaw = firstMatch(in: entry, pattern: #"<published>(.*?)</published>"#) ?? ""

        return LancerLiveVideo(
            id: decodeXMLEntities(videoID),
            title: decodeXMLEntities(title),
            watchURL: watchURL,
            thumbnailURL: thumbnailURL,
            publishedAt: parseDate(publishedRaw)
        )
    }

    private func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[captureRange])
    }

    private func decodeXMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
