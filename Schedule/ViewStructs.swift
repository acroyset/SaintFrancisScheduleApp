//
//  ViewStructs.swift
//  Schedule
//
//  Created by Andreas Royset on 8/15/25.
//

import Foundation
import SwiftUI

struct ClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var isPortrait: Bool
    
    @State var selector = 0
    
    var body: some View {
        if (iPad || isPortrait){
            VphoneClassEditor(
                data: $data,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor,
                isPortrait: isPortrait
            )
        } else {
            HphoneClassEditor(
                data: $data,
                PrimaryColor: PrimaryColor,
                SecondaryColor: SecondaryColor,
                TertiaryColor: TertiaryColor
            )
        }
    }
}

struct ClassProgressBar: View {
    var progress: Double      // 0...1
    var active: Bool          // highlight when current class
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color

    var body: some View {
        if active{
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(PrimaryColor.mix(with: .black, by: 0.4))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(TertiaryColor)
                        .frame(height: max(0, geo.size.height * progress))
                }
            }
        }
    }
}

struct OutlinedTextFieldStyle: TextFieldStyle {
    var cornerRadius: CGFloat = 10
    var lineWidth: CGFloat = 1
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12) // inner padding
            .background(
                TertiaryColor,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PrimaryColor.opacity(0.3), lineWidth: lineWidth) // inside the bounds
            )
    }
}

struct Background: View {
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        TertiaryColor.ignoresSafeArea()
    }
}

struct TextFieldClassEditor: View {
    @Binding var inputText: String
    var defaultText: String
    
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        TextField(defaultText, text: $inputText)
        .font(.system(
            size: iPad ? 20 : 14,
            weight: .bold,
            design: .monospaced
        ))
        .padding(12)
        .foregroundStyle(
            PrimaryColor)
        .background(SecondaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
    
struct VphoneClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var isPortrait: Bool
    
    var body: some View {
        VStack{
            Text("Edit Classes")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(
                    PrimaryColor.opacity(1))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            
            Divider()
            
            
            let indices: [Int] = [0, 1, 2, 3, 4, 5, 6, 9, 12]

            ForEach(indices, id: \.self) { (number: Int) in
                HStack{
                    if number <= 6{
                        TextFieldClassEditor(
                            inputText: $data.classes[number].name,
                            defaultText: "Period \(number + 1)",
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor
                        )
                    } else {
                        Text(data.classes[number].name)
                            .frame(maxWidth: .infinity, alignment: .leading) // Move this up
                            .font(.system(
                                size: iPad ? 20 : 14,
                                weight: .bold,
                                design: .monospaced
                            ))
                            .padding(12)
                            .foregroundStyle(PrimaryColor)
                            .background(SecondaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    
                    TextFieldClassEditor(
                        inputText: $data.classes[number].teacher,
                        defaultText: "Teacher",
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor,
                    )
                    
                    TextFieldClassEditor(
                        inputText: $data.classes[number].room,
                        defaultText: "Room #",
                        PrimaryColor: PrimaryColor,
                        SecondaryColor: SecondaryColor,
                        TertiaryColor: TertiaryColor
                    )
                    .frame(maxWidth: iPad ? .infinity : 60)
                }
            }
        }
        .padding(12)
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black, radius: 30)
        .frame(
            minWidth: iPad ? (isPortrait ? 600 : 1000) : 350,
            maxWidth: iPad ? (isPortrait ? 600 : 1000) : 350,
            minHeight: iPad ? 750 : 200,
            maxHeight: iPad ? 750 : 200
        )
    }
}

struct HphoneClassEditor: View {
    @Binding var data: ScheduleData
    var PrimaryColor: Color
    var SecondaryColor: Color
    var TertiaryColor: Color
    
    var body: some View {
        VStack{
            Text("Edit Classes")
                .font(.system(
                    size: iPad ? 34 : 22,
                    weight: .bold,
                    design: .monospaced
                ))
                .padding(12)
                .foregroundStyle(
                    PrimaryColor.opacity(1))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            
            Divider()
            
            HStack{
                let indices: [Int] = [0, 1, 2, 3, 4, 5, 6, 9, 12]
                
                ForEach(indices, id: \.self) { (number: Int) in
                    VStack{
                        if number <= 6{
                            TextFieldClassEditor(
                                inputText: $data.classes[number].name,
                                defaultText: "Period \(number + 1)",
                                PrimaryColor: PrimaryColor,
                                SecondaryColor: SecondaryColor,
                                TertiaryColor: TertiaryColor
                            )
                        } else {
                            Text(data.classes[number].name)
                                .frame(maxWidth: .infinity, alignment: .leading) // Move this up
                                .font(.system(
                                    size: iPad ? 20 : 14,
                                    weight: .bold,
                                    design: .monospaced
                                ))
                                .padding(12)
                                .foregroundStyle(PrimaryColor)
                                .background(SecondaryColor)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        
                        TextFieldClassEditor(
                            inputText: $data.classes[number].teacher,
                            defaultText: "Teacher",
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor,
                        )
                        
                        TextFieldClassEditor(
                            inputText: $data.classes[number].room,
                            defaultText: "Room #",
                            PrimaryColor: PrimaryColor,
                            SecondaryColor: SecondaryColor,
                            TertiaryColor: TertiaryColor
                        )
                        .frame(maxWidth: iPad ? .infinity : 60)
                    }
                }
            }
        }
        .padding(12)
        .background(TertiaryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black, radius: 30)
        .frame(
            minWidth: 800,
            maxWidth: 800,
            minHeight: 150,
            maxHeight: 150
        )
    }
}
