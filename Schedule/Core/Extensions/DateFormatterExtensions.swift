//
//  DateFormatterExtensions.swift
//  Schedule
//
//  Created by Andreas Royset on 11/18/25.
//

import SwiftUI

extension DateFormatter {
    static let eventDate: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df
    }()
}
