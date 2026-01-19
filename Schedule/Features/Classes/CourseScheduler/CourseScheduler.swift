import SwiftUI

// MARK: - Models
struct NextCourse : Codable {
    let courseId: String
    let grade: String
    let requirements: [String]
    
    init(courseId: String, grade: String = "Any", requirements: [String] = []) {
        self.courseId = courseId
        self.grade = grade
        self.requirements = requirements
    }
}

struct Course: Identifiable, Codable {
    let id: String
    let name: String
    let requirements: [String]
    let nextCourses: [NextCourse]
    let semester: String // "Full Year", "Semester"
    let isHonorsAP: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, requierments, nextCourses, semester, isHonorsAP
    }
    
    // For Codable conformance, prerequisites need special handling
    init(id: String, name: String, requirements: [String], nextCourses: [NextCourse],
         semester: String, isHonorsAP: Bool) {
        self.id = id
        self.name = name
        self.requirements = requirements
        self.nextCourses = nextCourses
        self.semester = semester
        self.isHonorsAP = isHonorsAP
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        requirements = try container.decode([String].self, forKey: .requierments)
        nextCourses = try container.decode([NextCourse].self, forKey: .nextCourses)
        semester = try container.decode(String.self, forKey: .semester)
        isHonorsAP = try container.decode(Bool.self, forKey: .isHonorsAP)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(requirements, forKey: .requierments)
        try container.encode(nextCourses, forKey: .nextCourses)
        try container.encode(semester, forKey: .semester)
        try container.encode(isHonorsAP, forKey: .isHonorsAP)
    }
}

// MARK: - Filtering
enum SubjectArea: String, CaseIterable, Identifiable {
    case all = "All"

    case english = "English"
    case math = "Math"
    case science = "Science"
    case worldLanguage = "World Language"
    case socialStudies = "Social Studies"
    case vpa = "Visual & Performing Arts"
    case ethnicStudies = "Ethnic Studies"
    case csEngineeringDesign = "CS / Engineering / Design"
    case healthFitness = "Health & Fitness"
    case religiousStudies = "Religious Studies"

    var id: String { rawValue }
}

enum CourseLevel: String, CaseIterable, Identifiable {
    case all = "All"
    case regular = "Regular"
    case honors = "Honors"
    case ap = "AP"

    var id: String { rawValue }
}

enum GradeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case grade9 = "9th"
    case grade10 = "10th"
    case grade11 = "11th"
    case grade12 = "12th"

    var id: String { rawValue }
}

extension Course {

    // Uses your ID prefixes (most reliable)
    var subjectArea: SubjectArea {
        let lowerId = id.lowercased()

        if lowerId.hasPrefix("en") || lowerId.hasPrefix("eng_") || lowerId == "readlab" {
            return .english
        }

        if lowerId.hasPrefix("math_") { return .math }
        if lowerId.hasPrefix("sci_") { return .science }

        // World Language: Spanish/French/Chinese/ASL
        if lowerId.hasPrefix("sp") || lowerId.hasPrefix("fr") || lowerId.hasPrefix("ch") || lowerId.hasPrefix("asl") {
            return .worldLanguage
        }

        if lowerId.hasPrefix("ss_") || lowerId.hasPrefix("ap_world") || lowerId.hasPrefix("ap_ushist") || lowerId.hasPrefix("ap_usgov") || lowerId.hasPrefix("ap_macro") || lowerId.hasPrefix("ap_psych") {
            return .socialStudies
        }

        if lowerId.hasPrefix("vpa_") || lowerId == "ap_musictheory" {
            return .vpa
        }

        if lowerId.hasPrefix("ethnic_") { return .ethnicStudies }

        if lowerId.hasPrefix("cs_") || lowerId.hasPrefix("design_") || lowerId.hasPrefix("ap_csp") || lowerId.hasPrefix("ap_csa") {
            return .csEngineeringDesign
        }

        if lowerId.hasPrefix("hf_") { return .healthFitness }

        if lowerId.hasPrefix("relig_") || lowerId == "relig1" {
            return .religiousStudies
        }

        // Fallback
        return .english
    }

    // Course level (AP vs Honors vs Regular)
    var courseLevel: CourseLevel {
        let n = name.lowercased()
        if n.contains("ap ") || n.hasPrefix("ap") { return .ap }
        if n.contains("honors") || isHonorsAP { return .honors }
        return .regular
    }

    // Grade filter based on requirements text
    var gradeTag: GradeFilter {
        let r = requirements.joined(separator: " ").lowercased()

        // Your strings include: "Current Freshmen", "Sophomore (10th grade) standing",
        // "11th/12th grade standing", "Senior (12th grade) standing", etc.
        // If multiple grades are allowed, this returns the earliest grade as a "tag".
        // (Filtering logic below will handle multi-grade correctly.)
        if r.contains("fresh") || r.contains("9th") || r.contains("9th grade") { return .grade9 }
        if r.contains("soph")  || r.contains("10th") || r.contains("10th grade") { return .grade10 }
        if r.contains("jun")   || r.contains("11th") || r.contains("11th grade") { return .grade11 }
        if r.contains("sen")   || r.contains("12th") || r.contains("12th grade") { return .grade12 }

        return .all
    }

    // Better: supports multi-grade requirements like "10th/11th/12th grade standing"
    func matches(gradeFilter: GradeFilter) -> Bool {
        if gradeFilter == .all { return true }

        let r = requirements.joined(separator: " ").lowercased()

        switch gradeFilter {
        case .grade9:
            return r.contains("fresh") || r.contains("9th")
        case .grade10:
            return r.contains("soph") || r.contains("10th")
        case .grade11:
            return r.contains("jun") || r.contains("11th")
        case .grade12:
            return r.contains("sen") || r.contains("12th")
        case .all:
            return true
        }
    }
}



// MARK: - ViewModel
@MainActor class CourseViewModel: ObservableObject {
    @Published var allCourses: [Course] = []
    @Published var searchText: String = ""
    @Published var selectedCourse: Course?
    
    @Published var selectedSubject: SubjectArea = .all
    @Published var selectedLevel: CourseLevel = .all
    @Published var selectedGrade: GradeFilter = .all
    
    var filteredResults: [Course] {
        allCourses
            .filter { course in
                if !searchText.isEmpty &&
                    !course.name.localizedCaseInsensitiveContains(searchText) {
                    return false
                }

                if selectedSubject != .all && course.subjectArea != selectedSubject {
                    return false
                }

                if selectedLevel != .all && course.courseLevel != selectedLevel {
                    return false
                }

                if !course.matches(gradeFilter: selectedGrade) {
                    return false
                }

                return true
            }
            .sorted { $0.name < $1.name }
    }
    
    func clearFilters() {
        selectedSubject = .all
        selectedLevel = .all
        selectedGrade = .all
    }
    
    func getCourse(byId id: String) -> Course? {
        allCourses.first { $0.id == id }
    }
    
    func getRequierments(for course: Course) -> [String] {
        return course.requirements
    }
    
    func getNextCourses(for course: Course) -> [Course] {
        course.nextCourses.compactMap { getCourse(byId: $0.courseId) }
    }
    
    func getNextCoursesRequierments(for course: Course) -> [NextCourse] {
        course.nextCourses
    }
}

struct CourseSchedulingView: View {
    @ObservedObject var courseViewModel: CourseViewModel
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    @Binding var window: classWindow
    
    var body: some View {
        ZStack{
            VStack(spacing: 0) {
                
                if let selected = courseViewModel.selectedCourse {
                    CourseDetailView(
                        course: selected,
                        viewModel:courseViewModel,
                        onCourseSelected: { course in
                            courseViewModel.selectedCourse = course
                        },
                        onBack: {
                            courseViewModel.selectedCourse = nil
                        },
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                } else {
                    SearchBar(
                        text: $courseViewModel.searchText,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    
                    FilterBar(
                        vm: courseViewModel,
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    
                    CourseListView(
                        courses: courseViewModel.filteredResults,
                        onCourseSelected: { course in
                            courseViewModel.selectedCourse = course
                        },
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                }
            }
            .padding(.top, iPad ? 60 : 50)
            
            VStack{
                
                if #available(iOS 26.0, *) {
                    HStack {
                        Text("Course Scheduler")
                            .font(.system(
                                size: iPad ? 34 : 22,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .padding(iPad ? 16 : 12)
                            .padding(.horizontal, iPad ? 20 : 16)
                        
                        Spacer()
                        
                        Button(action: { window = .None }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: iPad ? 30 : 26))
                                .foregroundStyle(PrimaryColor)
                        }
                        .padding(iPad ? 16 : 12)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(PrimaryColor)
                    .glassEffect()
                } else {
                    HStack {
                        Text("Course Scheduler")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(PrimaryColor)
                        
                        Spacer()
                        
                        Button(action: { window = .None }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(PrimaryColor)
                        }
                    }
                    .padding(20)
                    .background(SecondaryColor)
                    .cornerRadius(16)
                }
                
                
                Spacer()
            }
        }
    }
}

struct SearchBar: View {
    
    @Binding var text: String
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(PrimaryColor)
            ZStack{
                if text.isEmpty {
                    Text("Search courses...")
                        .foregroundColor(PrimaryColor.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("", text: $text)
                    .foregroundColor(PrimaryColor)
            }
        }
        .padding(12)
        .background(SecondaryColor)
        .cornerRadius(12)
        .padding(12)
    }
}

struct CourseListView: View {
    let courses: [Course]
    let onCourseSelected: (Course) -> Void
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        if courses.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundColor(PrimaryColor)
                Text("No courses found").font(.headline).foregroundColor(PrimaryColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TertiaryColor)
        } else {
            List(courses) { course in
                Button(action: { onCourseSelected(course) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.headline)
                                .foregroundColor(PrimaryColor)
                        }

                        Spacer()

                        if course.isHonorsAP {
                            Text(course.name.contains("AP") ? "AP" : "H")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(TertiaryColor)
                                .padding(4)
                                .background(
                                    course.name.contains("AP")
                                    ? Color.orange
                                    : Color.purple
                                )
                                .cornerRadius(3)
                        }
                    }
                    .padding(16)
                    .background(SecondaryColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .padding(.bottom, 16)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .mask{
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

struct CourseDetailView: View {
    let course: Course
    let viewModel: CourseViewModel
    let onCourseSelected: (Course) -> Void
    let onBack: () -> Void
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var requierments: [String] {
        viewModel.getRequierments(for: course)
    }
    
    var nextCourses: [Course] {
        viewModel.getNextCourses(for: course)
    }
    
    var nextCoursesRequierments: [NextCourse] {
        viewModel.getNextCoursesRequierments(for: course)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(PrimaryColor)
                    }
                    Spacer()
                }
                .padding(.top, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ContentSection(
                            course: course,
                            requierments: requierments,
                            nextCourses: nextCourses,
                            nextCoursesRequierments: nextCoursesRequierments,
                            onCourseSelected: onCourseSelected,
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor
                        )
                        Spacer(minLength: 50)
                    }
                }
            }
        }
    }
}

struct CourseBtn: View {
    let course: Course
    let minGrade: String
    let requierments: [String]
    let onTap: () -> Void
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name).font(.subheadline).fontWeight(.semibold).foregroundColor(PrimaryColor)
                }
                
                Spacer()
                
                VStack(spacing: 6) {
                    if minGrade != "Any" {
                        Text("Min: \(minGrade)").font(.caption2).fontWeight(.semibold).foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2).background(PrimaryColor).cornerRadius(4)
                    }
                    
                    ForEach(requierments, id: \.self) { req in
                        Text(req).font(.caption).foregroundColor(TertiaryColor.highContrastTextColor())
                    }
                }
                .padding(.horizontal, 8)
                
                Image(systemName: "chevron.right").font(.caption).foregroundColor(TertiaryColor.highContrastTextColor())
            }
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PrimaryColor, lineWidth: 2)
            )
        }
    }
}

struct Info: View {
    let course: Course
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name).font(.title2).fontWeight(.bold).foregroundStyle(PrimaryColor)
            }
            Spacer()
            if course.isHonorsAP {
                Text(course.name.contains("AP") ? "AP" : "Honors")
                    .font(.caption)
                    .foregroundStyle(TertiaryColor)
                    .padding(6)
                    .background(course.name.contains("AP") ? Color.orange : Color.purple)
                    .cornerRadius(4)
            }
        }
        Text(course.semester).font(.caption2).foregroundColor(TertiaryColor.highContrastTextColor())
    }
}

struct Requierments: View {
    let requierments: [String]
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        VStack{
            Text("Requirements")
                .font(.headline)
                .frame(alignment: .leading)
                .foregroundStyle(PrimaryColor)
                .padding(8)
            
            if requierments.isEmpty {
                Text("No requirements required")
                    .font(.subheadline)
                    .foregroundColor(TertiaryColor.highContrastTextColor())
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .cornerRadius(6)
            } else {
                VStack(spacing: 8) {
                    ForEach(requierments, id: \.self) { req in
                        Text(req)
                            .font(.caption)
                            .foregroundColor(TertiaryColor.highContrastTextColor())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct ContentSection: View {
    let course: Course
    let requierments: [String]
    let nextCourses: [Course]
    let nextCoursesRequierments: [NextCourse]
    let onCourseSelected: (Course) -> Void
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color

    private var nextPairs: [(Course, NextCourse)] {
        Array(zip(nextCourses, nextCoursesRequierments))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            VStack(alignment: .leading, spacing: 8) {
                Info(
                    course: course,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Requierments(
                    requierments: requierments,
                    PrimaryColor: PrimaryColor,
                    SecondaryColor: SecondaryColor,
                    TertiaryColor: TertiaryColor
                )
            }
            .padding(.horizontal)
            
            Divider()

            nextCoursesSection
                .padding(.horizontal)
                .padding(.bottom)
        }
    }

    @ViewBuilder
    private var nextCoursesSection: some View {
        Text("Next Available Courses").font(.headline).foregroundStyle(PrimaryColor)

        if nextPairs.isEmpty {
            Text("No follow-up courses")
                .font(.subheadline)
                .foregroundColor(TertiaryColor.highContrastTextColor())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(6)
        } else {
            VStack(spacing: 8) {
                ForEach(nextPairs, id: \.0.id) { (course, meta) in
                    CourseBtn(
                        course: course,
                        minGrade: meta.grade,
                        requierments: meta.requirements,
                        onTap: { onCourseSelected(course) },
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                    )
                }
            }
        }
    }
}

struct FilterBar: View {
    @ObservedObject var vm: CourseViewModel

    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {

                Menu {
                    Picker("Subject", selection: $vm.selectedSubject) {
                        ForEach(SubjectArea.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                } label: {
                    chipLabel("Subject", value: vm.selectedSubject.rawValue)
                }

                Menu {
                    Picker("Level", selection: $vm.selectedLevel) {
                        ForEach(CourseLevel.allCases) { l in
                            Text(l.rawValue).tag(l)
                        }
                    }
                } label: {
                    chipLabel("Level", value: vm.selectedLevel.rawValue)
                }

                Menu {
                    Picker("Grade", selection: $vm.selectedGrade) {
                        ForEach(GradeFilter.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                } label: {
                    chipLabel("Grade", value: vm.selectedGrade.rawValue)
                }

                Button {
                    vm.clearFilters()
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrimaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(SecondaryColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(PrimaryColor.opacity(0.35), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private func chipLabel(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrimaryColor.opacity(0.7))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrimaryColor)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(PrimaryColor.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SecondaryColor)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(PrimaryColor.opacity(0.35), lineWidth: 1)
        )
    }
}

