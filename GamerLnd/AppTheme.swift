//
//  AppTheme.swift
//  GamerLnd
//
//  Created by Patrick  Flood on 9/30/25.
//


// AppTheme.swift
// Centralized typography and spacing helpers.

import SwiftUI

struct AppTheme {
    struct Spacing {
        static let s: CGFloat = 6
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    struct Fonts {
        static let title = Font.title3.weight(.semibold)
        static let body = Font.body
        static let caption = Font.caption
        static let footnote = Font.footnote
    }
}
