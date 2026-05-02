//
//  OnboardingView.swift
//  Schedule
//
//  Created by Andreas Royset on 3/19/26.
//
//
//  Shown once after a user's first sign-in.
//  Lets them fill in their 7 class names before entering the app.
//  Stored in UserDefaults so it never shows again after completion or skip.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    var onComplete: ([ClassItem]) -> Void

    @State private var classes: [ClassItem] = Array(
        repeating: ClassItem(name: "", teacher: "", room: ""),
        count: 7
    )
    @State private var expandedIndex: Int? = nil
    @State private var currentFocus: FocusField? = nil

    enum FocusField: Hashable {
        case name(Int), teacher(Int), room(Int)
    }

    private let periodNames = [
        "Period 1", "Period 2", "Period 3", "Period 4",
        "Period 5", "Period 6", "Period 7"
    ]
    private let namePlaceholders = [
        "e.g. AP Biology", "e.g. English 2 Honors", "e.g. Algebra 2",
        "e.g. US History", "e.g. Spanish 3", "e.g. Chemistry", "e.g. PE / Elective"
    ]

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                    .padding(.top, 8)

                Text("Set Up Your Classes")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Enter your class names. Tap a row to also add teacher and room.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .onTapGesture { dismissKeyboard() }

            Divider()

            // ── Class rows ───────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        ClassEntryRow(
                            index: i,
                            item: $classes[i],
                            periodName: periodNames[i],
                            namePlaceholder: namePlaceholders[i],
                            isExpanded: expandedIndex == i,
                            currentFocus: $currentFocus,
                            onTapRow: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    expandedIndex = expandedIndex == i ? nil : i
                                }
                            },
                            onSubmitName: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    expandedIndex = i
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    currentFocus = .teacher(i)
                                }
                            },
                            onSubmitTeacher: {
                                currentFocus = .room(i)
                            },
                            onSubmitRoom: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    expandedIndex = nil
                                }
                                if i < 6 {
                                    currentFocus = .name(i + 1)
                                } else {
                                    dismissKeyboard()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 200)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { dismissKeyboard() }

            Divider()

            // ── Action buttons ───────────────────────────────────────────
            VStack(spacing: 10) {
                Button {
                    dismissKeyboard()
                    saveAndEnter()
                } label: {
                    Text(hasAnyName ? "Save & Enter App" : "Enter App")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    dismissKeyboard()
                    skip()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20)
        .padding(.horizontal, 20)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                currentFocus = .name(0)
            }
        }
    }

    // MARK: - Helpers

    private var hasAnyName: Bool {
        classes.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private func saveAndEnter() {
        let trimmed = classes.map {
            ClassItem(
                name: $0.name.trimmingCharacters(in: .whitespaces),
                teacher: $0.teacher.trimmingCharacters(in: .whitespaces),
                room: $0.room.trimmingCharacters(in: .whitespaces)
            )
        }
        onComplete(trimmed)
        markOnboardingDone()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func skip() {
        onComplete([])
        markOnboardingDone()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func markOnboardingDone() {
        UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
        NotificationSettings.requestAuthorizationAfterOnboardingIfNeeded()
        NotificationCenter.default.post(name: .backToSchoolPromptEligibilityChanged, object: nil)
    }
}

// MARK: - Single class entry row

private struct ClassEntryRow: View {
    let index: Int
    @Binding var item: ClassItem
    let periodName: String
    let namePlaceholder: String
    let isExpanded: Bool
    @Binding var currentFocus: OnboardingView.FocusField?
    let onTapRow: () -> Void
    let onSubmitName: () -> Void
    let onSubmitTeacher: () -> Void
    let onSubmitRoom: () -> Void

    @FocusState private var focusedField: OnboardingView.FocusField?

    private var hasContent: Bool {
        !item.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Main row (always visible) ────────────────────────────────
            HStack(spacing: 12) {
                // Period badge
                Text("P\(index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isExpanded ? .white : .blue)
                    .frame(width: 32, height: 32)
                    .background(isExpanded ? Color.blue : Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Class name field
                TextField(namePlaceholder, text: $item.name)
                    .font(.system(size: 15))
                    .focused($focusedField, equals: .name(index))
                
                // Expand / detail indicator
                HStack(spacing: 4) {
                    if !item.teacher.isEmpty && !item.room.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .onTapGesture { onTapRow() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())

            // ── Expanded detail (teacher + room) ─────────────────────────
            if isExpanded {
                VStack(spacing: 8) {
                    Divider().padding(.horizontal, 12)

                    HStack(spacing: 10) {
                        // Teacher
                        HStack(spacing: 6) {
                            Image(systemName: "person")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            TextField("Teacher", text: $item.teacher)
                                .font(.system(size: 14))
                                .focused($focusedField, equals: .teacher(index))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Room
                        HStack(spacing: 6) {
                            Image(systemName: "mappin")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            TextField("Room", text: $item.room)
                                .font(.system(size: 14))
                                .focused($focusedField, equals: .room(index))
                        }
                        .frame(maxWidth: 110)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isExpanded ? Color.blue.opacity(0.06) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isExpanded ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: currentFocus) { _, newFocus in
            focusedField = newFocus
        }
        .onChange(of: focusedField) { _, newFocus in
            // Sync back so parent knows where focus is
            if newFocus != nil { currentFocus = newFocus }
        }
    }
}
