//
//  DataManager.swift
//  Schedule
//

import FirebaseFirestore

@MainActor
class DataManager: ObservableObject {
    private let db = Firestore.firestore()
    
    func saveToCloud(classes: [ClassItem], theme: ThemeColors, isSecondLunch: [Bool], for userId: String) async throws {
        let classesData = classes.map { classItem in
            [
                "name": classItem.name,
                "teacher": classItem.teacher,
                "room": classItem.room
            ]
        }
        
        let themeDict: [String: String] = [
            "primary": theme.primary,
            "secondary": theme.secondary,
            "tertiary": theme.tertiary
        ]
        
        try await db.collection("users").document(userId).setData([
            "classes": classesData,
            "theme": themeDict,
            "isSecondLunch": isSecondLunch,
            "lastUpdated": Timestamp()
        ], merge: true)
    }
    
    func loadFromCloud(for userId: String) async throws -> ([ClassItem], ThemeColors, [Bool]) {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data() else {
            return ([], ThemeColors(primary: "#00A5FFFF", secondary: "#00A5FF19", tertiary: "#FFFFFFFF"), [false, false])
        }
        
        let classesArray = (data["classes"] as? [[String: String]]) ?? []
        let classes = classesArray.map { dict in
            ClassItem(
                name: dict["name"] ?? "",
                teacher: dict["teacher"] ?? "",
                room: dict["room"] ?? ""
            )
        }
        
        let themeDict = (data["theme"] as? [String: String]) ?? [:]
        let theme = ThemeColors(
            primary: themeDict["primary"] ?? "#00A5FFFF",
            secondary: themeDict["secondary"] ?? "#00A5FF19",
            tertiary: themeDict["tertiary"] ?? "#FFFFFFFF"
        )
        
        let isSecondLunch = (data["isSecondLunch"] as? [Bool]) ?? [false, false]
        
        return (classes, theme, isSecondLunch)
    }
    
    func deleteUserData(for userId: String) async throws {
        try await db.collection("users").document(userId).delete()
    }
    
    func recordPolicyAcceptance(for userId: String, version: String) async throws {
        try await db.collection("users").document(userId).setData([
            "privacyPolicy": [
                "accepted": true,
                "version": version,
                "timestamp": FieldValue.serverTimestamp()
            ]
        ], merge: true)
    }
}
