// Toast.swift
// Standard success/error toast with auto-dismiss. No ShapeStyle.ultraBlack dependency.

import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    var kind: Kind
    var message: String
    var duration: TimeInterval = 2.2
}

struct ToastView: View {
    let toast: Toast
    var bottomInset: CGFloat = 0

    private var bg: Color {
        switch toast.kind {
        case .success: return ColorTheme.accent.opacity(0.22)
        case .error:   return Color.red.opacity(0.22)
        case .info:    return Color.gray.opacity(0.22)
        }
    }
    private var stroke: Color {
        switch toast.kind {
        case .success: return ColorTheme.accent.opacity(0.55)
        case .error:   return Color.red.opacity(0.55)
        case .info:    return Color.gray.opacity(0.55)
        }
    }
    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(toast.message).lineLimit(2)
        }
        .font(.footnote.weight(.semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bg)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, max(24, bottomInset + 78))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let t = toast {
                ToastView(toast: t, bottomInset: 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + t.duration) {
                            withAnimation { toast = nil }
                        }
                    }
            }
        }
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        self.modifier(ToastModifier(toast: toast))
    }
}
