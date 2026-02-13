//
//  PrivacyPolicyView.swift
//  GamerLnd
//
//  Created by Patrick  Flood on 9/30/25.
//


// PrivacyPolicyView.swift
// Simple in-app privacy policy. Customize content as needed.

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Policy")
                    .font(.title2).bold()
                Text("Last updated: February 6, 2026")

                Text("""
We collect minimal data to power core features:
• Authentication (Email/Password or Sign in with Apple via Firebase)
• Game logs, likes, follows, comments
• Optional analytics (with your consent)

Data use:
• Provide feed, profiles, and search
• Improve app quality and reliability
• No sale of personal data

Your choices:
• Delete your account in Settings
• Manage your content and reports

Security:
• Stored in Firebase; access restricted by rules

Contact:
• programming.pf@gmail.com
""")
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
