// SupportView.swift
// Simple support / contact screen.

import SwiftUI

struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Support")
                    .font(.title2).bold()

                Text("Need help? We usually respond within 48 hours.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Link("Email support: programming.pf@gmail.com", destination: URL(string: "mailto:programming.pf@gmail.com")!)
                    .font(.footnote.weight(.semibold))

                Text("Common topics:")
                    .font(.footnote.weight(.semibold))

                Text("""
• Account access
• Content reports
• Bugs or crashes
""")
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
