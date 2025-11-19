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
