// OnboardingTips.swift
// Lightweight coach-mark bubble.

import SwiftUI

struct CoachTip: View {
    let text: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundColor(ColorTheme.accent)
                Text(text)
                    .font(.footnote)
                    .foregroundColor(ColorTheme.text)
            }
            HStack {
                Spacer()
                Button {
                    onDismiss?()
                } label: {
                    Text("Got it").font(.caption.weight(.semibold))
                }
                .tint(ColorTheme.accent)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(radius: 8)
    }
}
