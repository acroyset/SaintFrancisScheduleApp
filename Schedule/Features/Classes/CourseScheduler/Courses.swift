//
//  Courses.swift
//  Schedule
//
//  Created by Andreas Royset on 1/13/26.
//

import SwiftUI

func loadSFHSCourses() -> [Course] {
    let start = DispatchTime.now()
    
    let allCourses = [
        
        Course(
            id: "en1",
            name: "English 1",
            requirements: ["Current Freshmen"],
            nextCourses: [
                NextCourse(courseId: "en2"),
                NextCourse(courseId: "en2h", grade: "A-")
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "en1h",
            name: "English 1 Honors",
            requirements: ["Current Freshmen", "HSPT Placment Test Scores"],
            nextCourses: [
                NextCourse(courseId: "en2h")
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "readLab",
            name: "Reading Lab",
            requirements: [
                "9th grade standing",
                "Placement determined by entrance exam scores",
                "English 1 must be taken concurrently"
            ],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "en2",
            name: "English 2",
            requirements: ["Current Sophmore"],
            nextCourses: [
                NextCourse(courseId: "en3"),
                NextCourse(courseId: "APenLang", grade: "Any", requirements: ["Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "en2h",
            name: "English 2 Honors",
            requirements: ["Current Sophmore", "Current English 1 Honors Student", "Current English 1 Student with A-"],
            nextCourses: [
                NextCourse(courseId: "en3"),
                NextCourse(courseId: "APenLang", grade: "Any", requirements: ["Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "en3",
            name: "English 3: British Literature and Analytical Writing",
            requirements: [
                "Current Junior",
                "Semester 2 Selective required"
            ],
            nextCourses: [
                NextCourse(courseId: "en4"),
                NextCourse(courseId: "APenLit", grade: "Any", requirements: ["Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "APenLang",
            name: "AP English Language",
            requirements: [
                "Informed enrollment",
                "Contract Required"
            ],
            nextCourses: [
                NextCourse(courseId: "en4"),
                NextCourse(courseId: "APenLit", grade: "Any", requirements: ["Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "en3_activist",
            name: "Activist Literature",
            requirements: [
                "English 3 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en3_dystopian",
            name: "Dystopian Literature",
            requirements: [
                "English 3 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en3_feminist",
            name: "Feminist Literature",
            requirements: [
                "English 3 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en3_indigenous",
            name: "Indigenous People’s Literature",
            requirements: [
                "English 3 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en3_modernDrama",
            name: "Modern Drama",
            requirements: [
                "English 3 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en3_sportsCulture",
            name: "Sports, Literature, and Culture",
            requirements: [
                "English 3 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en4",
            name: "English 4: World Literature",
            requirements: [
                "Current Senior",
                "Semester 2 Selective required"
            ],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "APenLit",
            name: "AP English Literature",
            requirements: [
                "Informed enrollment",
                "Contract Required"
            ],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "en4_scifiFantasy",
            name: "Science Fiction & Fantasy",
            requirements: [
                "English 4 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en4_contempAuthors",
            name: "Contemporary American Authors",
            requirements: [
                "English 4 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en4_sportsInLit",
            name: "Sports in Literature",
            requirements: [
                "English 4 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en4_filmAsLit",
            name: "Film as Literature",
            requirements: [
                "English 4 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en4_cultureVoice",
            name: "Culture and Voice",
            requirements: [
                "English 4 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "en4_contempPoetry",
            name: "Contemporary Poetry",
            requirements: [
                "English 4 Semester 2 Selective"
            ],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        // =========================
        // MARK: - Math
        // =========================
        
        Course(
            id: "math_alg1",
            name: "Algebra 1",
            requirements: ["Placement by Math Department / incoming placement"],
            nextCourses: [
                NextCourse(courseId: "math_descGeo"),
                NextCourse(courseId: "math_geo", grade: "C"),
                NextCourse(courseId: "math_geoH", grade: "A"),
                NextCourse(courseId: "math_summerGeo", grade: "C")
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_alg1h",
            name: "Algebra 1 Honors",
            requirements: ["Placement by Math Department / incoming placement"],
            nextCourses: [
                NextCourse(courseId: "math_geo", grade: "C"),
                NextCourse(courseId: "math_geoH", grade: "B"),
                NextCourse(courseId: "math_summerGeo", grade: "C")
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_alg1ab",
            name: "Algebra 1A/1B",
            requirements: ["Placement by Math Department"],
            nextCourses: [
                NextCourse(courseId: "math_descGeo"),
                NextCourse(courseId: "math_geo", grade: "A"),
                NextCourse(courseId: "math_summerGeo", grade: "A", requirements: ["Teacher Recommendation"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_descGeo",
            name: "Descriptive Geometry",
            requirements: ["Successful completion of Algebra 1A/1B OR Algebra 1 students who do not meet prerequisites for Geometry"],
            nextCourses: [
                NextCourse(courseId: "math_alg2", grade: "A-"),
                NextCourse(courseId: "math_alg2")
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_geo",
            name: "Geometry",
            requirements: ["Minimum of C in Algebra 1 or Algebra 1H OR minimum of A in Algebra 1A/1B"],
            nextCourses: [
                NextCourse(courseId: "math_intAlg"),
                NextCourse(courseId: "math_alg2", grade: "C"),
                NextCourse(courseId: "math_alg2h", grade: "A-"),
                NextCourse(courseId: "math_advAlg2TrigH", grade: "Any", requirements: ["Qualifying Exam + previous math grades"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_geoH",
            name: "Honors Geometry",
            requirements: ["Minimum of B in Algebra 1H OR minimum of A in Algebra 1"],
            nextCourses: [
                NextCourse(courseId: "math_alg2h", grade: "B"),
                NextCourse(courseId: "math_alg2", grade: "Any")
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_summerGeo",
            name: "Summer Geometry",
            requirements: ["Minimum of C in Algebra 1 or Algebra 1H OR minimum of A + Teacher Recommendation in Algebra 1A/1B"],
            nextCourses: [
                NextCourse(courseId: "math_alg2", grade: "Any"),
                NextCourse(courseId: "math_alg2h", grade: "A-")
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_intAlg",
            name: "Intermediate Algebra",
            requirements: ["Successful completion of Descriptive Geometry OR Geometry students who do not meet prerequisites for Algebra 2"],
            nextCourses: [
                NextCourse(courseId: "math_alg2", grade: "Any"),
                NextCourse(courseId: "math_trigAnalytic", grade: "A")
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_alg2",
            name: "Algebra 2",
            requirements: ["Minimum of C in both Geometry and Algebra 1 (or equivalent placement)"],
            nextCourses: [
                NextCourse(courseId: "math_prec", grade: "B"),
                NextCourse(courseId: "math_trigAnalytic", grade: "C"),
                NextCourse(courseId: "math_stats", grade: "Any", requirements: ["Senior standing"]),
                NextCourse(courseId: "math_summerTrig", grade: "A", requirements: ["to enroll in AP Precalculus"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_alg2h",
            name: "Algebra 2 Honors",
            requirements: ["Minimum of B in previous Honors class OR minimum of A- in college prep class"],
            nextCourses: [
                NextCourse(courseId: "math_prec", grade: "B-"),
                NextCourse(courseId: "math_trigAnalytic", grade: "C-"),
                NextCourse(courseId: "math_stats", grade: "Any", requirements: ["Senior standing"]),
                NextCourse(courseId: "math_summerTrig", grade: "B", requirements: ["to enroll in AP Precalculus"]),
                NextCourse(courseId: "math_apPrec", grade: "A")
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_advAlg2TrigH",
            name: "Advanced Algebra 2/Trigonometry Honors",
            requirements: ["Qualifying exam + previous math grades (Math Department placement)"],
            nextCourses: [
                NextCourse(courseId: "math_apPrec", grade: "B"),
                NextCourse(courseId: "math_calc", grade: "B"),
                NextCourse(courseId: "math_apCalcAB", grade: "A-", requirements: ["Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_trigAnalytic",
            name: "Trigonometry/Analytic Geometry",
            requirements: ["Minimum of C in Algebra 2 OR A in Intermediate Algebra (or equivalent placement)"],
            nextCourses: [
                NextCourse(courseId: "math_prec", grade: "C-"),
                NextCourse(courseId: "math_apPrec", grade: "A"),
                NextCourse(courseId: "math_stats", grade: "Any", requirements: ["Senior standing"]),
                NextCourse(courseId: "math_apStats", grade: "B-", requirements: ["Senior standing"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_summerTrig",
            name: "Summer Trigonometry",
            requirements: ["For AP Precalculus placement (see math prerequisites)"],
            nextCourses: [
                NextCourse(courseId: "math_apPrec", grade: "B+"),
                NextCourse(courseId: "math_prec", grade: "Any", requirements: ["Auto-move if Summer Trig grade below requirement"])
            ],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_prec",
            name: "Precalculus",
            requirements: ["Minimum of C- (if coming from Trigonometry) OR B- (if from Algebra 2 Honors) OR B (if from Algebra 2)"],
            nextCourses: [
                NextCourse(courseId: "math_calc", grade: "B"),
                NextCourse(courseId: "math_apCalcAB", grade: "A"),
                NextCourse(courseId: "math_stats", grade: "Any", requirements: ["Senior standing"]),
                NextCourse(courseId: "math_apStats", grade: "B-", requirements: ["Senior standing"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_apPrec",
            name: "AP Precalculus",
            requirements: ["Informed enrollment + prerequisite grades (see guide)"],
            nextCourses: [
                NextCourse(courseId: "math_calc", grade: "B-"),
                NextCourse(courseId: "math_apCalcAB", grade: "B+", requirements: ["Contract Required"]),
                NextCourse(courseId: "math_apStats", grade: "B-", requirements: ["Senior standing", "Contract Required"]),
                NextCourse(courseId: "math_stats", grade: "Any", requirements: ["Senior standing"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_calc",
            name: "Calculus",
            requirements: ["Minimum of B in Precalculus OR equivalent placement"],
            nextCourses: [
                NextCourse(courseId: "math_ode", grade: "Any"),
                NextCourse(courseId: "math_apStats", grade: "Any", requirements: ["Senior standing"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_apCalcAB",
            name: "AP Calculus AB",
            requirements: ["Minimum prerequisites (see guide) + Contract Required when applicable"],
            nextCourses: [
                NextCourse(courseId: "math_apCalcBC", grade: "B-", requirements: ["Contract Required"]),
                NextCourse(courseId: "math_apStats", grade: "Any", requirements: ["Senior standing", "Contract Required"]),
                NextCourse(courseId: "math_stats", grade: "Any", requirements: ["Senior standing"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_apCalcBC",
            name: "AP Calculus BC",
            requirements: ["Successful completion of AP Calculus AB/BC sequence + Contract Required when applicable"],
            nextCourses: [
                NextCourse(courseId: "math_ode"),
                NextCourse(courseId: "math_apStats", grade: "Any", requirements: ["Senior standing", "Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "math_ode",
            name: "Ordinary Differential Equations",
            requirements: ["Successful completion of AP Calculus BC"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_stats",
            name: "Statistics",
            requirements: ["Senior standing"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "math_apStats",
            name: "AP Statistics",
            requirements: ["Senior standing", "Contract Required"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        // =========================
        // MARK: - Science
        // =========================
        
        Course(
            id: "sci_bio",
            name: "Biology",
            requirements: ["Freshman science option"],
            nextCourses: [
                NextCourse(courseId: "sci_chem"),
                NextCourse(courseId: "sci_chemH", grade: "Any", requirements: ["A in Biology OR B in Biology Honors", "Qualifying exam", "Contract Required"]),
                NextCourse(courseId: "sci_conPhys")
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_bioH",
            name: "Biology Honors",
            requirements: ["Incoming freshman option (informed by math placement + reading score)"],
            nextCourses: [
                NextCourse(courseId: "sci_chem"),
                NextCourse(courseId: "sci_chemH", grade: "Any", requirements: ["A in Biology OR B in Biology Honors", "Qualifying exam", "Contract Required"]),
                NextCourse(courseId: "sci_conPhys")
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "sci_chem",
            name: "Chemistry",
            requirements: ["10th/11th/12th grade standing", "Completion of Biology or Biology Honors", "Algebra 2 or higher recommended concurrently"],
            nextCourses: [
                NextCourse(courseId: "sci_phys", grade: "B-", requirements: ["Trigonometry or higher concurrently"]),
                NextCourse(courseId: "sci_physH", grade: "A", requirements: ["Trig-based course B or higher"]),
                NextCourse(courseId: "sci_exSci", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"]),
                NextCourse(courseId: "sci_envSci", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"]),
                NextCourse(courseId: "sci_marineBio", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_chemH",
            name: "Chemistry Honors",
            requirements: ["10th/11th/12th grade standing", "Completion of Biology with A or Biology Honors with B or higher", "Algebra 2+ required concurrently", "Qualifying exam + prior grades", "Contract Required"],
            nextCourses: [
                NextCourse(courseId: "sci_phys", grade: "B-", requirements: ["Trigonometry or higher concurrently"]),
                NextCourse(courseId: "sci_physH", grade: "B", requirements: ["Trig-based course B or higher"]),
                NextCourse(courseId: "sci_exSci", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"]),
                NextCourse(courseId: "sci_envSci", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"]),
                NextCourse(courseId: "sci_marineBio", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "sci_conPhys",
            name: "Conceptual Physics",
            requirements: ["10th/11th/12th grade standing", "Successful completion of Biology/Biology Honors and Algebra 1", "This is the only Physics course a student will take"],
            nextCourses: [
                NextCourse(courseId: "sci_exSci", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"]),
                NextCourse(courseId: "sci_envSci", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"]),
                NextCourse(courseId: "sci_marineBio", requirements: ["11th/12th grade standing", "Biology + Physical Science complete"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_phys",
            name: "Physics",
            requirements: ["10th/11th/12th grade standing", "Completion of Biology or Chemistry with B- or higher OR Honors with C+ or higher", "Trigonometry or higher required concurrently"],
            nextCourses: [
                NextCourse(courseId: "sci_apBio", requirements: ["Senior", "Completed Biology + Chemistry + Physics", "Contract Required"]),
                NextCourse(courseId: "sci_apChem", requirements: ["Senior", "Completed Biology + Chemistry + Physics", "Contract Required"]),
                NextCourse(courseId: "sci_apPhysC", requirements: ["Senior", "Completed Biology + Chemistry + Physics", "Prior calculus is required", "Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_physH",
            name: "Physics Honors",
            requirements: ["10th/11th/12th grade standing", "Completion of Biology or Chemistry with A OR Honors with B or higher", "Trig-based course with B or higher required"],
            nextCourses: [
                NextCourse(courseId: "sci_apBio", requirements: ["Senior", "Completed Biology + Chemistry + Physics", "Contract Required"]),
                NextCourse(courseId: "sci_apChem", requirements: ["Senior", "Completed Biology + Chemistry + Physics", "Contract Required"]),
                NextCourse(courseId: "sci_apPhysC", requirements: ["Senior", "Completed Biology + Chemistry + Physics", "Prior calculus is required", "Contract Required"])
            ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "sci_exSci",
            name: "Exercise Science & Sports Medicine",
            requirements: ["11th/12th grade standing", "Completion of Biology and Physical Science requirement", "Course offering dependent upon enrollment"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_envSci",
            name: "Environmental Science",
            requirements: ["11th/12th grade standing", "Completion of Biology and Physical Science", "Course offering dependent upon enrollment"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_marineBio",
            name: "Marine Biology",
            requirements: ["11th/12th grade standing", "Completion of Biology and Physical Science", "Course offering dependent upon enrollment"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "sci_apEnvSci",
            name: "AP Environmental Science",
            requirements: ["11th/12th grade standing", "Completion of Biology and Chemistry", "Completion of Bio or Chem with A OR Honors with B or higher", "Contract Required", "Summer reading required"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "sci_apBio",
            name: "AP Biology",
            requirements: ["Limited/informed enrollment", "Senior", "Completed Biology + Chemistry + Physics", "Contract Required", "Extra lab period weekly"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "sci_apChem",
            name: "AP Chemistry",
            requirements: ["Limited/informed enrollment", "Senior", "Completed Biology + Chemistry + Physics", "Contract Required", "Extra lab period weekly"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "sci_apPhysC",
            name: "AP Physics C",
            requirements: ["Limited/informed enrollment", "Senior", "Completed Biology + Chemistry + Physics", "Calculus-based; prior calculus required", "Contract Required"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        // =========================
        // MARK: - World Language
        // =========================
        
        Course(
            id: "sp1",
            name: "Spanish 1",
            requirements: ["Placement (Level 1) or proficiency placement exam"],
            nextCourses: [ NextCourse(courseId: "sp2") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "sp2",
            name: "Spanish 2",
            requirements: ["Successful completion of Spanish 1"],
            nextCourses: [ NextCourse(courseId: "sp3"), NextCourse(courseId: "sp3h") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "sp3",
            name: "Spanish 3",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "sp4"), NextCourse(courseId: "ap_spLang") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "sp3h",
            name: "Spanish 3 Honors",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "sp4"), NextCourse(courseId: "ap_spLang") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        Course(
            id: "sp4",
            name: "Spanish 4",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency"],
            nextCourses: [ NextCourse(courseId: "ap_spLit") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "ap_spLang",
            name: "AP Spanish Language",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency"],
            nextCourses: [ NextCourse(courseId: "ap_spLit") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        Course(
            id: "ap_spLit",
            name: "AP Spanish Literature",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "fr1",
            name: "French 1",
            requirements: ["Placement (Level 1) or proficiency placement exam"],
            nextCourses: [ NextCourse(courseId: "fr2") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "fr2",
            name: "French 2",
            requirements: ["Successful completion of French 1"],
            nextCourses: [ NextCourse(courseId: "fr3"), NextCourse(courseId: "fr3h") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "fr3",
            name: "French 3",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "fr4"), NextCourse(courseId: "ap_frLang") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "fr3h",
            name: "French 3 Honors",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "fr4"), NextCourse(courseId: "ap_frLang") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        Course(
            id: "fr4",
            name: "French 4",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "fr5h") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "ap_frLang",
            name: "AP French Language",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency"],
            nextCourses: [ NextCourse(courseId: "fr5h") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        Course(
            id: "fr5h",
            name: "French 5 Honors",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "ch1",
            name: "Chinese 1",
            requirements: ["Placement (Level 1) or proficiency placement exam"],
            nextCourses: [ NextCourse(courseId: "ch2") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "ch2",
            name: "Chinese 2",
            requirements: ["Successful completion of Chinese 1"],
            nextCourses: [ NextCourse(courseId: "ch3"), NextCourse(courseId: "ch3h") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "ch3",
            name: "Chinese 3",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "ch4"), NextCourse(courseId: "ap_chinese") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "ch3h",
            name: "Chinese 3 Honors",
            requirements: ["Ability to demonstrate novice (mid-high) to intermediate proficiency"],
            nextCourses: [ NextCourse(courseId: "ch4"), NextCourse(courseId: "ap_chinese") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        Course(
            id: "ch4",
            name: "Chinese 4",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "ap_chinese",
            name: "AP Chinese",
            requirements: ["Ability to demonstrate intermediate to advanced proficiency", "Summer reading/prep required", "Contract required"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "asl1",
            name: "American Sign Language 1",
            requirements: ["Priority to diagnosed language-based learning disabilities / deaf or hard of hearing / CODA; otherwise space-available"],
            nextCourses: [ NextCourse(courseId: "asl2") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "asl2",
            name: "American Sign Language 2",
            requirements: ["Successful completion of ASL 1"],
            nextCourses: [ NextCourse(courseId: "asl3") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "asl3",
            name: "American Sign Language 3",
            requirements: ["Minimum of C in ASL 2"],
            nextCourses: [ NextCourse(courseId: "aslConv") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(
            id: "aslConv",
            name: "American Sign Language Conversation",
            requirements: ["Completion of the two-year language requirement in Spanish, Chinese, or French"],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        // =========================
        // MARK: - Social Studies
        // =========================
        
        Course(
            id: "ss_world",
            name: "World History",
            requirements: ["Sophomore (10th grade) standing"],
            nextCourses: [ NextCourse(courseId: "ss_usHist") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "ap_world",
            name: "AP World History",
            requirements: ["10th grade standing", "Informed enrollment", "Minimum B in English 1 Honors OR A in English 1", "Placement exam", "Contract required"],
            nextCourses: [ NextCourse(courseId: "ap_usHist") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "ss_usHist",
            name: "US History",
            requirements: ["Junior (11th grade) standing"],
            nextCourses: [ NextCourse(courseId: "ss_usGov"), NextCourse(courseId: "ss_econ"), NextCourse(courseId: "ap_usGov") ],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "ap_usHist",
            name: "AP US History",
            requirements: ["11th grade standing", "Informed enrollment", "Contract required"],
            nextCourses: [ NextCourse(courseId: "ap_usGov"), NextCourse(courseId: "ap_macro") ],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "ss_usGov",
            name: "US Government",
            requirements: ["Senior (12th grade) standing"],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "ss_econ",
            name: "Economics",
            requirements: ["Senior (12th grade) standing"],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "ap_usGov",
            name: "AP US Government",
            requirements: ["Informed enrollment", "Contract required (may not drop once enrolled)", "Summer reading required"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "ap_macro",
            name: "AP Macroeconomics",
            requirements: ["12th grade standing", "Informed enrollment", "Contract required", "Suggested concurrent Calculus or higher"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        // Social Studies Electives
        Course(id: "ss_bioEthics", name: "Biomedical Ethics", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "ss_finLit", name: "Financial Literacy", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "ss_olympics", name: "History and Politics of the Olympics", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "ss_socialism", name: "History and Theory of Socialism", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "ss_psychIntro", name: "Introduction to Psychology", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        Course(
            id: "ap_psych",
            name: "AP Psychology",
            requirements: ["11th or 12th grade standing", "Informed enrollment", "Strong grades in prior SS + English (see guide)", "Contract required"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        // =========================
        // MARK: - Visual & Performing Arts (VPA)
        // =========================
        
        // Introductory VPA courses (to meet requirement)
        Course(id: "vpa_basicDesign1", name: "Basic Design / Drawing 1", requirements: ["Introductory VPA option"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_yearbookBeg", name: "Beginning Yearbook", requirements: ["Introductory VPA option"], nextCourses: [NextCourse(courseId: "vpa_yearbook2")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_dvp1", name: "Digital Video Production 1", requirements: ["Introductory VPA option"], nextCourses: [NextCourse(courseId: "vpa_dvp2")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_graphicArts", name: "Graphic Arts", requirements: ["Introductory VPA option"], nextCourses: [NextCourse(courseId: "vpa_advPhoto")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_drama1", name: "Drama 1", requirements: ["Introductory VPA option"], nextCourses: [NextCourse(courseId: "vpa_drama2", grade: "B"), NextCourse(courseId: "vpa_drama2ab", grade: "B")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_concertBand1", name: "Concert Band 1", requirements: ["At least one year of music lessons and/or band experience", "Course fee required"], nextCourses: [NextCourse(courseId: "vpa_band2")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_choir1", name: "Choir 1", requirements: ["Introductory VPA option"], nextCourses: [NextCourse(courseId: "vpa_concertChoir2")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_dance1", name: "Dance 1", requirements: ["Introductory VPA option"], nextCourses: [NextCourse(courseId: "vpa_dance2")], semester: "Full Year", isHonorsAP: false),
        
        // VPA electives
        Course(id: "vpa_dance2", name: "Dance 2", requirements: ["Successful completion of Dance 1"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_actMusTheater", name: "Acting for Musical Theater", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        Course(
            id: "vpa_drama2",
            name: "Drama 2",
            requirements: ["Minimum of B in Drama 1", "Full year course"],
            nextCourses: [NextCourse(courseId: "vpa_drama3", grade: "B", requirements: ["Teacher recommendation"])],
            semester: "Full Year",
            isHonorsAP: false
        ),
        Course(id: "vpa_drama2ab", name: "Drama 2A/2B", requirements: ["Minimum of B in Drama 1", "Semester course"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "vpa_drama3", name: "Drama 3", requirements: ["Minimum of B in Drama 2", "Teacher recommendation"], nextCourses: [NextCourse(courseId: "vpa_drama4")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_drama4", name: "Drama 4", requirements: ["Successful completion of Drama 1, 2, and 3"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_ceramics1", name: "3D Design: Ceramics 1", requirements: ["Successful completion of a year of visual or performing arts"], nextCourses: [NextCourse(courseId: "vpa_ceramics2", grade: "B")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_ceramics2", name: "3D Design: Ceramics 2", requirements: ["Minimum of B in Ceramics 1 OR Department Chair approval"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_dig2dAnim", name: "Digital 2D Animation", requirements: ["Successful completion of a year of visual or performing arts"], nextCourses: [NextCourse(courseId: "vpa_advDig2dAnim2")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_advDig2dAnim2", name: "Advanced Digital 2D Animation 2", requirements: ["Successful completion of Digital 2D Animation"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_digPhoto", name: "Digital Photography", requirements: ["Graphic Arts OR successful completion of a year of visual or performing arts"], nextCourses: [NextCourse(courseId: "vpa_advPhoto")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_dvp2", name: "Digital Video Production 2", requirements: ["Successful completion of DVP1 OR Department Chair approval"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_drawComp2", name: "Drawing and Composition 2", requirements: ["Successful completion of a year of visual or performing arts"], nextCourses: [NextCourse(courseId: "vpa_advStudioArt")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_paint1", name: "Painting 1", requirements: ["Successful completion of a year of visual or performing arts"], nextCourses: [NextCourse(courseId: "vpa_advStudioArt")], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_advPhoto", name: "Advanced Photography", requirements: ["Graphic Arts, Video Production OR Department Chair approval"], nextCourses: [NextCourse(courseId: "vpa_advStudioArt")], semester: "Full Year", isHonorsAP: false),
        
        Course(
            id: "vpa_advStudioArt",
            name: "Advanced Studio Art",
            requirements: ["Year-long beginning design course + one intermediate course (see guide)"],
            nextCourses: [NextCourse(courseId: "vpa_apStudioArt")],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "vpa_apStudioArt",
            name: "AP Studio Art",
            requirements: ["12th grade standing", "Department Chair approval", "Summer work required", "Zero period"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        // Music ensembles
        Course(id: "vpa_bandTech", name: "Band Tech", requirements: ["Open to all students", "No prior instrumental music experience"], nextCourses: [NextCourse(courseId: "vpa_concertBand1")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_band2", name: "Band 2", requirements: ["Successful completion of concert band"], nextCourses: [NextCourse(courseId: "vpa_band3")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_band3", name: "Band 3", requirements: ["Successful completion of concert band"], nextCourses: [NextCourse(courseId: "vpa_band4")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_band4", name: "Band 4", requirements: ["Successful completion of concert band"], nextCourses: [NextCourse(courseId: "vpa_band5")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_band5", name: "Band 5", requirements: ["10th/11th/12th grade standing", "Successful completion of concert band"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_trebleChoir", name: "Treble Choir", requirements: [], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_concertChoir2", name: "Concert Choir 2", requirements: [], nextCourses: [NextCourse(courseId: "vpa_concertChoir3")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_concertChoir3", name: "Concert Choir 3", requirements: [], nextCourses: [NextCourse(courseId: "vpa_concertChoir4")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_concertChoir4", name: "Concert Choir 4", requirements: [], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(id: "vpa_chamberChoir", name: "Chamber Choir", requirements: ["Audition-only choir"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_jazzEns", name: "Jazz Ensemble", requirements: ["Band Director approval + audition", "Zero period"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_stringEnsIntro", name: "Introduction to String Ensemble", requirements: ["Background on a string instrument"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(
            id: "ap_musicTheory",
            name: "AP Music Theory",
            requirements: ["11th/12th grade standing", "Must read musical notation", "Some familiarity with keyboard"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(id: "vpa_symphBand2", name: "Symphonic Band 2", requirements: ["Advanced ensemble participation requirements (see guide)"], nextCourses: [NextCourse(courseId: "vpa_symphBand3")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_symphBand3", name: "Symphonic Band 3", requirements: ["Advanced ensemble participation requirements (see guide)"], nextCourses: [NextCourse(courseId: "vpa_symphBand4")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_symphBand4", name: "Symphonic Band 4", requirements: ["Advanced ensemble participation requirements (see guide)"], nextCourses: [NextCourse(courseId: "vpa_symphBand5")], semester: "Full Year", isHonorsAP: false),
        Course(id: "vpa_symphBand5", name: "Symphonic Band 5", requirements: ["Advanced ensemble participation requirements (see guide)"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        // =========================
        // MARK: - Ethnic Studies
        // =========================
        
        Course(
            id: "ethnic_intro",
            name: "Ethnic Studies",
            requirements: ["One semester course", "10th/11th/12th grade standing"],
            nextCourses: [
                NextCourse(courseId: "ethnic_apAAS"),
                NextCourse(courseId: "vpa_artResistance"),
                NextCourse(courseId: "relig_racialJusticeChurch"),
                NextCourse(courseId: "en3_activist"),
                NextCourse(courseId: "en3_feminist"),
                NextCourse(courseId: "en3_indigenous"),
                NextCourse(courseId: "en3_sportsCulture"),
                NextCourse(courseId: "en4_cultureVoice"),
                NextCourse(courseId: "en4_contempPoetry")
            ],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        Course(
            id: "ethnic_apAAS",
            name: "AP African American Studies",
            requirements: ["11th/12th grade standing", "Can be taken after Ethnic Studies intro OR stand-alone", "Fulfills Ethnic Studies requirement"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        // =========================
        // MARK: - College Prep Electives (English Dept)
        // =========================
        
        Course(id: "eng_debate", name: "Argumentation & Debate", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "eng_creativeWriting", name: "Creative Writing", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "eng_speech1", name: "Speech 1", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        Course(id: "vpa_yearbook2", name: "Journalism: Yearbook Design & Production 2A/2B", requirements: ["Beginning Yearbook"], nextCourses: [NextCourse(courseId: "vpa_yearbook3h")], semester: "Semester", isHonorsAP: false),
        Course(id: "vpa_yearbook3h", name: "Advanced Yearbook: Yearbook Design & Production 3 Honors", requirements: ["Beginning Yearbook or demonstrate competency"], nextCourses: [NextCourse(courseId: "vpa_yearbook4h")], semester: "Full Year", isHonorsAP: true),
        Course(id: "vpa_yearbook4h", name: "Advanced Yearbook: Yearbook Design & Production 4 Honors", requirements: ["Beginning Yearbook or demonstrate competency"], nextCourses: [], semester: "Full Year", isHonorsAP: true),
        
        // =========================
        // MARK: - College Prep Electives (Design Dept / CS / Engineering)
        // =========================
        
        Course(id: "design_biotech", name: "BioTechnology", requirements: ["11th/12th grade standing", "Completion of Biology and Chemistry"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        Course(
            id: "cs_panda",
            name: "Computer Science: Principles and Algorithms (CS PANDA)",
            requirements: ["Good understanding of Algebra 1 concepts", "At least B average in high school math"],
            nextCourses: [NextCourse(courseId: "ap_csp"), NextCourse(courseId: "ap_csa")],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "ap_csp",
            name: "AP Computer Science Principles",
            requirements: ["To take as a sophomore: CS PANDA or equivalent intro CS by May with minimum B"],
            nextCourses: [NextCourse(courseId: "ap_csa")],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(
            id: "ap_csa",
            name: "AP Computer Science A",
            requirements: ["Contract required", "Junior: completed CS PANDA or AP CSP or Trigonometry+ with B", "Senior: may be concurrently enrolled in Trigonometry+ to take"],
            nextCourses: [],
            semester: "Full Year",
            isHonorsAP: true
        ),
        
        Course(id: "design_creativeApps", name: "Creative Apps for Mobile Devices", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "design_designThinking", name: "Design Thinking", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        Course(id: "design_engineering", name: "Engineering", requirements: ["11th/12th grade standing", "Completion of Biology and a physical science with minimum B"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        Course(id: "design_entrepreneurship", name: "Entrepreneurship", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "design_indInquiry", name: "Independent Inquiry", requirements: ["11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "design_innovationRWE", name: "Innovation Program: Real World Experience", requirements: [], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        Course(id: "design_robotics1", name: "Robotics 1", requirements: [], nextCourses: [NextCourse(courseId: "design_robotics2")], semester: "Full Year", isHonorsAP: false),
        Course(id: "design_robotics2", name: "Robotics 2", requirements: ["Completion of Robotics 1 OR year in Robotics Club + competition", "Requires participation in Robotics Club for second semester"], nextCourses: [], semester: "Full Year", isHonorsAP: false),
        
        // =========================
        // MARK: - Health & Fitness (Electives)
        // =========================
        
        Course(id: "hf_funcStrength", name: "Functional Strength and Mobility", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_speedPower", name: "Speed, Power, and Agility", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_advSNC1", name: "Advanced Strength and Conditioning 1", requirements: ["10th/11th/12th grade standing"], nextCourses: [NextCourse(courseId: "hf_advSNC2")], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_advSNC2", name: "Advanced Strength and Conditioning 2", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_advTeam1", name: "Advanced Team Sports 1", requirements: ["10th/11th/12th grade standing"], nextCourses: [NextCourse(courseId: "hf_advTeam2")], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_advTeam2", name: "Advanced Team Sports 2", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_mindfulness", name: "The Science and Practice of Mindfulness", requirements: ["10th/11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "hf_foundHumanMove", name: "Foundational Human Movement", requirements: ["11th/12th grade standing"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        // =========================
        // MARK: - Religious Studies
        // =========================
        
        Course(
            id: "relig1",
            name: "Religion 1: Sacred Stories",
            requirements: ["Freshman required course"],
            nextCourses: [NextCourse(courseId: "relig_hebrewNT")],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "relig_hebrewNT",
            name: "Hebrew Scripture / New Testament",
            requirements: ["Required course"],
            nextCourses: [NextCourse(courseId: "relig_ethicsJustice")],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "relig_ethicsJustice",
            name: "Ethical Reasoning and Social Justice",
            requirements: ["Required course"],
            nextCourses: [NextCourse(courseId: "relig_christVoc")],
            semester: "Full Year",
            isHonorsAP: false
        ),
        
        Course(
            id: "relig_christVoc",
            name: "Christian Vocation",
            requirements: ["Required (semester)", "Plus one additional Senior Selective"],
            nextCourses: [
                NextCourse(courseId: "relig_contempSpirituality"),
                NextCourse(courseId: "relig_designThinkingJustice"),
                NextCourse(courseId: "relig_philosophyIntro"),
                NextCourse(courseId: "relig_racialJusticeChurch"),
                NextCourse(courseId: "relig_sportsSpirituality"),
                NextCourse(courseId: "relig_spiritualEcology"),
                NextCourse(courseId: "relig_hpTheology"),
                NextCourse(courseId: "relig_worldReligions")
            ],
            semester: "Semester",
            isHonorsAP: false
        ),
        
        // Senior Religion Selectives
        Course(id: "relig_contempSpirituality", name: "Contemporary Christian Spirituality", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_designThinkingJustice", name: "Design Thinking for Justice", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_philosophyIntro", name: "Introduction to Philosophy", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_racialJusticeChurch", name: "Racial Justice and the American Church", requirements: ["Senior Religion Selective", "Fulfills second semester of Ethnic Studies"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_sportsSpirituality", name: "Sports and Spirituality", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_spiritualEcology", name: "Spiritual Ecology", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_hpTheology", name: "Theological Perspectives in Modern Adolescent Literature: A Christian Reading of Harry Potter", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        Course(id: "relig_worldReligions", name: "World Religions", requirements: ["Senior Religion Selective"], nextCourses: [], semester: "Semester", isHonorsAP: false),
        
        // =========================
        // MARK: - Interdisciplinary Ethnic Studies (VPA)
        // =========================
        Course(
            id: "vpa_artResistance",
            name: "Art & Resistance",
            requirements: ["Interdisciplinary Ethnic Studies course (counts toward Ethnic Studies pathway)"],
            nextCourses: [],
            semester: "Semester",
            isHonorsAP: false
        ),
        
    ]
    
    
    let end = DispatchTime.now()
    let ms = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
    print("Loaded Courses in \(String(format: "%.3f", ms)) ms")
    
    return allCourses
}
