//
//  UpdatePromptView.swift
//  Schedule
//
//  Created by Andreas Royset on 12/3/25.
//

import Foundation
import SwiftUI

struct UpdatePromptView: View {
    @StateObject private var checker = VersionChecker()
    @State private var showUpdate = false
    
    let appID = "6751200514"
    
    var body: some View {
        EmptyView()
            .onAppear {
                checker.fetchLatestVersion(appID: appID)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let latest = checker.latestVersion {
                        
                        if isUpdateAvailable(current: version, latest: latest) {
                            showUpdate = true
                        }
                    }
                }
            }
            .alert("New Version Available", isPresented: $showUpdate) {
                Button("Update") {
                    openAppStore(appID: appID)
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("A newer version of the app is available. Would you like to update?")
            }
    }
    
    func openAppStore(appID: String) {
        let url = URL(string: "https://apps.apple.com/app/id\(appID)")!
        UIApplication.shared.open(url)
    }
}
