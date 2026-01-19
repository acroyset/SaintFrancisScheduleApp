//
//  SchoologyConnect.swift
//  Schedule
//
//  Created by Andreas Royset on 1/16/26.
//

import SwiftUI

struct SchoologyConnectSheet: View {
    @Binding var isPresented: Bool
    @Binding var data: ScheduleData
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    
    @State private var isLoading = false
    @State private var selectedClasses: [SchoolClassItem] = []
    @State private var showingClassSelection = false
    
    @State private var classes: [SchoolClassItem] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Import Classes")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(PrimaryColor)
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(PrimaryColor)
                    }
                }
                .padding(16)
                .background(SecondaryColor)
                
                ScrollView {
                    VStack(spacing: 16) {
                        if !showingClassSelection {
                            // Initial state - Connect button
                            VStack(spacing: 20) {
                                Image(systemName: "book.circle")
                                    .font(.system(size: 50))
                                    .foregroundStyle(PrimaryColor)
                                
                                VStack(spacing: 8) {
                                    Text("Connect Your Schoology Account")
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundStyle(PrimaryColor)
                                    
                                    Text("Securely authenticate to import your class list")
                                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Button(action: connectToSchoology) {
                                    if isLoading {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .tint(PrimaryColor)
                                            Text("Connecting...")
                                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                        }
                                    } else {
                                        HStack(spacing: 10) {
                                            Image(systemName: "lock.open")
                                            Text("Connect with Schoology")
                                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(PrimaryColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .disabled(isLoading)
                                
                                Spacer()
                            }
                            .padding(20)
                        } else {
                            // Class selection state
                            VStack(spacing: 16) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.green)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Connected to Schoology")
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(PrimaryColor)
                                        Text("Select classes to import in period order")
                                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                                            .foregroundStyle(.gray)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(12)
                                .background(SecondaryColor)
                                .cornerRadius(8)
                                
                                Text("Your Classes")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(PrimaryColor)
                                
                                ForEach($classes, id: \.id) { $schoolClass in
                                    let selectedIndex = selectedClasses.firstIndex(where: { $0.id == schoolClass.id })
                                    
                                    ClassSelectionRow(
                                        schoolClass: schoolClass,
                                        isSelected: selectedClasses.contains(where: { $0.id == schoolClass.id }),
                                        primaryColor: PrimaryColor,
                                        secondaryColor: SecondaryColor,
                                        index: selectedIndex,
                                        action: {
                                            toggleClassSelection(schoolClass)
                                        }
                                    )
                                }
                                
                                Spacer()
                            }
                            .padding(20)
                        }
                    }
                }
                
                // Footer
                if showingClassSelection {
                    Button(action: importSelectedClasses) {
                        Text("Import \(selectedClasses.count) Class\(selectedClasses.count == 1 ? "" : "es")")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(selectedClasses.isEmpty ? Color.gray : PrimaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(selectedClasses.isEmpty)
                    .padding(16)
                    .background(SecondaryColor)
                }
            }
        }
        
        .onAppear(){
            classes = getMockClasses()
        }
    }
    
    private func connectToSchoology() {
        isLoading = true
        
        // Simulate OAuth flow and API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showingClassSelection = true
            isLoading = false
        }
    }
    
    private func getMockClasses() -> [SchoolClassItem] {
        // Mock data - replace with real API call once you have Schoology credentials
        return [
            SchoolClassItem(id: "1", name: "AP Biology", teacher: "Mrs. Smith", room: "213"),
            SchoolClassItem(id: "2", name: "US History", teacher: "Mr. Johnson", room: "105"),
            SchoolClassItem(id: "3", name: "Calculus II", teacher: "Dr. Chen", room: "301"),
            SchoolClassItem(id: "4", name: "English Literature", teacher: "Ms. Garcia", room: "215"),
            SchoolClassItem(id: "5", name: "Chemistry", teacher: "Dr. Patel", room: "118"),
            SchoolClassItem(id: "6", name: "Spanish 3", teacher: "Señorita Lopez", room: "202")
        ]
    }
    
    private func toggleClassSelection(_ schoolClass: SchoolClassItem) {
        if selectedClasses.contains(where: { $0.id == schoolClass.id }) {
            selectedClasses.removeAll { $0.id == schoolClass.id }
        } else {
            selectedClasses.append(schoolClass)
        }
    }
    
    private func importSelectedClasses() {
        // Map selected Schoology classes to your data model
        for (index, selectedClass) in selectedClasses.enumerated() {
            if index < 7 {
                data.classes[index].name = selectedClass.name
                data.classes[index].teacher = selectedClass.teacher
                data.classes[index].room = selectedClass.room
            }
        }
        
        isPresented = false
    }
}

// MARK: - Helper Components

struct ClassSelectionRow: View {
    var schoolClass: SchoolClassItem
    var isSelected: Bool
    var primaryColor: Color
    var secondaryColor: Color
    var index: Int?
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(primaryColor)
                        .frame(width: 32, height: 32)
                    
                    if isSelected {
                        Text("\((index ?? 0) + 1)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(schoolClass.name)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(primaryColor)
                    
                    HStack(spacing: 8) {
                        Text(schoolClass.teacher)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.gray)
                        
                        Text("•")
                            .foregroundStyle(.gray)
                        
                        Text("Room \(schoolClass.room)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(secondaryColor)
            .cornerRadius(8)
        }
    }
}

// MARK: - Data Models

struct SchoolClassItem: Identifiable {
    let id: String
    let name: String
    let teacher: String
    let room: String
}
