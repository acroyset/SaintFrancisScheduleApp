//
//  Constants.swift
//  Schedule
//

import SwiftUI

var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

func progressValue(start: Int, end: Int, now: Int) -> Double {
    guard end > start else { return 0 }
    if now <= start { return 0 }
    if now >= end { return 1 }
    return Double(now - start) / Double(end - start)
}

enum Window: Int {
    case Home = 0
    case News = 1
    case ClassesView = 2
    case Map = 3
    case Profile = 4
}

enum TutorialState: Int {
    case Hidden = 0
    case Intro = 1
    case DateNavigator = 2
    case News = 3
    case ClassesView = 4
    case Settings = 5
    case Profile = 6
    case Outro = 7
}

enum BackToSchoolPromptStorage {
    static let reminderPrompt2026 = "DidPromptBackToSchoolReminders2026"
    static let firstDayClassUpdateHandled2026 = "DidHandleFirstDayClassUpdate2026"
}

func classesDocumentsURL() throws -> URL {
    let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return docs.appendingPathComponent("Classes.txt")
}

@discardableResult
func ensureWritableClassesFile() throws -> URL {
    let dst = try classesDocumentsURL()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dst.path) {
        if let src = Bundle.main.url(forResource: "Classes", withExtension: "txt") {
            try? fm.copyItem(at: src, to: dst)
        } else {
            try "".write(to: dst, atomically: true, encoding: .utf8)
        }
    }
    return dst
}

func overwriteClassesFile(with classes: [ClassItem]) {
    do {
        let url = try ensureWritableClassesFile()
        let encoder = JSONEncoder()
        let text = try classes.map { item -> String in
            let data = try encoder.encode(item)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            return line
        }
        .joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        print("❌ overwriteClassesFile error:", error)
    }
}

func copyText(from sourcePath: String, to destinationPath: String) {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    let destinationURL = URL(fileURLWithPath: destinationPath)
    
    do {
        let text = try String(contentsOf: sourceURL, encoding: .utf8)
        try text.write(to: destinationURL, atomically: true, encoding: .utf8)
    } catch {
        print("❌ Error copying text: \(error)")
    }
}
 
