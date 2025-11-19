//
//  SettingsViewModel.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var selectedOption: SelectedOption = .none
    
    func toggleOption(_ option: SelectedOption) {
        if selectedOption == option {
            selectedOption = .none
        } else {
            selectedOption = option
        }
    }
}
