//
//  TutorialView.swift
//  Schedule
//
//  Extracted from ContentView.swift
//

import SwiftUI

struct TutorialView: View {
    @Binding var tutorial: TutorialState
    let PrimaryColor: Color
    let TertiaryColor: Color
    
    var body: some View {
        VStack {
            Text(title)
                .font(.system(
                    size: iPad ? 40 : 30,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
            
            Divider()
            
            Text(info)
                .font(.system(
                    size: iPad ? 24 : 15,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(PrimaryColor)
                .frame(alignment: .leading)
            
            HStack {
                Text("For more help visit our ")
                    .font(.footnote)
                    .foregroundStyle(TertiaryColor.highContrastTextColor())
                Text("support website")
                    .font(.footnote)
                    .foregroundColor(.blue)
                    .underline()
                    .onTapGesture {
                        if let url = URL(string: "https://sites.google.com/view/sf-schedule-help/home") {
                            UIApplication.shared.open(url)
                        }
                    }
            }
            
            HStack {
                Button {
                    if let x = TutorialState(rawValue: tutorial.rawValue - 1) {
                        tutorial = x
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                
                Spacer()
                
                Button {
                    if tutorial == .Outro {
                        tutorial = .Hidden
                    } else if let x = TutorialState(rawValue: tutorial.rawValue + 1) {
                        tutorial = x
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(8)
            .padding(.horizontal)
        }
        .padding(12)
        .frame(maxWidth: iPad ? 500 : 300)
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 20)
    }
    
    private var title: String {
        switch tutorial {
        case .Hidden: return "Error"
        case .Intro: return "Welcome to Schedule!"
        case .DateNavigator: return "Date Navigator"
        case .News: return "News"
        case .ClassEditor: return "Class Editor"
        case .Settings: return "Settings"
        case .Profile: return "Profile"
        case .Outro: return "Thanks!"
        }
    }
    
    private var info: String {
        switch tutorial {
        case .Hidden:
            return "Error"
        case .Intro:
            return "This is a schedule app for Saint Francis High School. It allows you to view your schedule, add new classes, and edit your existing ones!"
        case .DateNavigator:
            return "Access the date navigator by clicking on the date in the home screen.\n\nThis is how you can choose your dates for the whole year!"
        case .News:
            return "Access the news tab by clicking on the news icon in the toolbar.\n\nThis is where you can see current events like clubs football games and everything inbetween!"
        case .ClassEditor:
            return "Access the class editor by clicking on the edit class icon in the toolbar.\n\nThis is how you can edit your classes. You can also select if you are second lunch or not."
        case .Settings:
            return "Access the settings tab by clicking on the settings icon in the toolbar.\n\nThis is where you can change preferances like the color scheme!"
        case .Profile:
            return "Access the profile tab by clicking on the profile icon in the toolbar.\n\nThis is how you can sign out or sync your devices."
        case .Outro:
            return "Thanks for downloading Saint Francis Schedule! \n\nYou can find this tutorial in the Profile Menu."
        }
    }
}
