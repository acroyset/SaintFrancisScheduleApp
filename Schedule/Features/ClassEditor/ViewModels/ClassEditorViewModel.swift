//
//  ClassEditorViewModel.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

@MainActor
class ClassEditorViewModel: ObservableObject {
    @Published var scheduleData: ScheduleData
    
    init(scheduleData: ScheduleData) {
        self.scheduleData = scheduleData
    }
    
    func updateClass(at index: Int, name: String? = nil, teacher: String? = nil, room: String? = nil) {
        guard scheduleData.classes.indices.contains(index) else { return }
        
        if let name = name {
            scheduleData.classes[index].name = name
        }
        if let teacher = teacher {
            scheduleData.classes[index].teacher = teacher
        }
        if let room = room {
            scheduleData.classes[index].room = room
        }
        
        saveToFile()
    }
    
    func toggleSecondLunch() {
        scheduleData.isSecondLunch.toggle()
        saveToFile()
    }
    
    private func saveToFile() {
        overwriteClassesFile(with: scheduleData.classes)
    }
}
