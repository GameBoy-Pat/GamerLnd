// TermsOfServiceView.swift
// Simple in-app terms. Customize as needed.

import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Terms of Service")
                    .font(.title2).bold()
                Text("Last updated: February 6, 2026")

                Text("""
By using GamerLnd you agree to:
• Be respectful and avoid harassment or hate speech
• Only post content you have the right to share
• Avoid spam or malicious behavior

We may remove content or accounts that violate these rules.

If you have questions, contact programming.pf@gmail.com.
""")
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
    }
}
