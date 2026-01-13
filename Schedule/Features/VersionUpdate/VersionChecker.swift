//
//  VersionChecker.swift
//  Schedule
//
//  Created by Andreas Royset on 12/3/25.
//

import Foundation

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}


class VersionChecker: ObservableObject {
    @Published var latestVersion: String?
    
    func fetchLatestVersion(appID: String) {
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(appID)")!
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            if let result = try? JSONDecoder().decode(AppStoreLookup.self, from: data),
               let version = result.results.first?.version {
                DispatchQueue.main.async {
                    self.latestVersion = version
                }
            }
        }.resume()
    }
}

struct AppStoreLookup: Codable {
    let results: [AppStoreResult]
}

struct AppStoreResult: Codable {
    let version: String
}

func isUpdateAvailable(current: String, latest: String) -> Bool {
    return latest > current;
}
