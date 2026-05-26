//
//  SkeletonView.swift
//  GamerLnd
//
//  Created by Patrick  Flood on 10/14/25.
//


import SwiftUI

struct SkeletonView: View {
    var cornerRadius: CGFloat = 10
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.15), Color.gray.opacity(0.25)],
                                 startPoint: .leading, endPoint: .trailing))
            .redacted(reason: .placeholder)
            .shimmer()
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(gradient: Gradient(colors: [.clear, .white.opacity(0.35), .clear]),
                               startPoint: .leading, endPoint: .trailing)
                    .rotationEffect(.degrees(10))
                    .offset(x: phase * 300)
            )
            .onAppear {
                if phase < 1 {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
            }
    }
}
private extension View { func shimmer() -> some View { modifier(ShimmerModifier()) } }
