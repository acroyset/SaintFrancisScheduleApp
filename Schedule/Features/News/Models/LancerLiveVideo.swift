//
//  LancerLiveVideo.swift
//  Schedule
//

import Foundation

struct LancerLiveVideo: Identifiable, Equatable {
    let id: String
    let title: String
    let watchURL: URL
    let thumbnailURL: URL
    let publishedAt: Date?

    var publishedText: String {
        guard let publishedAt else { return "Recently" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: publishedAt)
    }

    func embedURL(origin: String) -> URL {
        var components = URLComponents(string: "https://www.youtube.com/embed/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "origin", value: origin)
        ]
        return components.url!
    }
}
