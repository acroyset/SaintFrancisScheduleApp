//
//  TextFieldClassEditor.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import Foundation
import SwiftUI

struct TextFieldClassEditor: View {
    @Binding var inputText: String
    var defaultText: String
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    var courseOptions: [Course] = []

    @FocusState private var isFocused: Bool

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [Course] {
        CourseAutocomplete.suggestions(from: courseOptions, matching: trimmedInput)
    }

    private var canAddCustomName: Bool {
        !courseOptions.isEmpty &&
            !trimmedInput.isEmpty &&
            !CourseAutocomplete.hasExactMatch(in: courseOptions, for: trimmedInput)
    }

    private var shouldShowAutocomplete: Bool {
        !courseOptions.isEmpty && isFocused && (!suggestions.isEmpty || canAddCustomName)
    }

    var body: some View {
        TextField(
            "",
            text: $inputText,
            prompt: Text(defaultText)
                .foregroundStyle(PrimaryColor.opacity(0.78))
        )
            .appThemeFont(.secondary, size: iPad ? 20 : 14, weight: .bold)
            .focused($isFocused)
            .padding(12)
            .foregroundStyle(PrimaryColor)
            .background(SecondaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .topLeading) {
                if shouldShowAutocomplete {
                    CourseAutocompleteMenu(
                        suggestions: suggestions,
                        customName: canAddCustomName ? trimmedInput : nil,
                        primaryColor: PrimaryColor,
                        secondaryColor: SecondaryColor,
                        onSelect: { name in
                            inputText = name
                            isFocused = false
                        }
                    )
                    .frame(width: CourseAutocomplete.menuWidth)
                    .offset(y: iPad ? 58 : 48)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .zIndex(shouldShowAutocomplete ? 1000 : 0)
            .onReceive(NotificationCenter.default.publisher(for: .dismissCourseAutocomplete)) { _ in
                isFocused = false
            }
    }
}

enum CourseAutocomplete {
    static var menuWidth: CGFloat {
        min(UIScreen.main.bounds.width - 48, iPad ? 440 : 360)
    }

    static let allCourses: [Course] = {
        loadSFHSCourses()
            .reduce(into: [Course]()) { courses, course in
                if !courses.contains(where: { $0.name.caseInsensitiveCompare(course.name) == .orderedSame }) {
                    courses.append(course)
                }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static func suggestions(from courses: [Course] = allCourses, matching query: String, limit: Int = 6) -> [Course] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return Array(courses.prefix(limit))
        }

        return Array(
            courses
                .filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
                .sorted { lhs, rhs in
                    let lhsStarts = lhs.name.localizedCaseInsensitiveComparePrefix(trimmedQuery)
                    let rhsStarts = rhs.name.localizedCaseInsensitiveComparePrefix(trimmedQuery)

                    if lhsStarts != rhsStarts {
                        return lhsStarts
                    }

                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    static func hasExactMatch(in courses: [Course] = allCourses, for name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return courses.contains { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    }
}

struct CourseAutocompleteMenu: View {
    let suggestions: [Course]
    let customName: String?
    let primaryColor: Color
    let secondaryColor: Color
    let onSelect: (String) -> Void

    var body: some View {
        if #available(iOS 26.0, *), AppAvailability.liquidGlass {
            menuContent
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(primaryColor.opacity(0.36), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        } else {
            menuContent
                .background(secondaryColor.opacity(0.99))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(primaryColor.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private var menuContent: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { course in
                Button {
                    onSelect(course.name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: course))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryColor)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .appThemeFont(.secondary, size: iPad ? 16 : 14, weight: .semibold)
                                .foregroundStyle(primaryColor)
                                .lineLimit(iPad ? 1 : 2)
                                .minimumScaleFactor(0.88)

                            Text(courseDetailText(for: course))
                                .appThemeFont(.secondary, style: .caption)
                                .foregroundStyle(primaryColor.opacity(0.65))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if course.id != suggestions.last?.id || customName != nil {
                    Divider().padding(.leading, 36)
                }
            }

            if let customName {
                Button {
                    onSelect(customName)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(width: 18)

                        Text("Add \"\(customName)\"")
                            .appThemeFont(.secondary, size: iPad ? 16 : 14, weight: .semibold)
                            .foregroundStyle(primaryColor)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func courseDetailText(for course: Course) -> String {
        switch course.courseLevel {
        case .ap:
            return "\(course.semester) - AP"
        case .honors:
            return "\(course.semester) - Honors"
        case .regular, .all:
            return course.semester
        }
    }

    private func iconName(for course: Course) -> String {
        switch course.courseLevel {
        case .ap:
            return "a.circle.fill"
        case .honors:
            return "star.circle.fill"
        case .regular, .all:
            return "book.closed"
        }
    }
}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
}
