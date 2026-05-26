import SwiftUI

struct GameLogOverlayHost: View {
    struct PreviewContext {
        let gameLog: GameLog
        let gameName: String
        let authorUsernameOverride: String?
        let focusCommentOnAppear: Bool
    }

    private enum Mode {
        case preview(PreviewContext)
        case editor(Game, startsWithExistingLog: Bool)
    }

    @State private var mode: Mode
    @State private var suppressHostChrome: Bool = false
    @State private var editorDismissRequestID: Int = 0
    let onClose: () -> Void

    init(preview: PreviewContext, onClose: @escaping () -> Void) {
        _mode = State(initialValue: .preview(preview))
        self.onClose = onClose
    }

    init(editor game: Game, onClose: @escaping () -> Void) {
        _mode = State(initialValue: .editor(game, startsWithExistingLog: false))
        self.onClose = onClose
    }

    private var modeTitle: String {
        switch mode {
        case .preview: return "Game Log Preview"
        case .editor: return "Game Log Editor"
        }
    }

    private var hostAccent: Color {
        switch mode {
        case .preview(let ctx):
            if let rating = ctx.gameLog.rating, rating > 0 {
                return ColorTheme.ratingBandColor(for: rating)
            }
            return ColorTheme.separator
        case .editor:
            return ColorTheme.accent
        }
    }

    private func formattedStatus(_ status: GameStatus) -> String {
        switch status {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .notPlayed: return "Not Started"
        }
    }

    var body: some View {
        ZStack {
            OverlayBackdrop()
                .ignoresSafeArea()
                .onTapGesture {
                    switch mode {
                    case .preview:
                        onClose()
                    case .editor:
                        editorDismissRequestID += 1
                    }
                }

            VStack(spacing: 0) {
                switch mode {
                case .preview(let ctx):
                    GameLogDetailView(
                        gameLog: ctx.gameLog,
                        gameName: ctx.gameName,
                        authorUsernameOverride: ctx.authorUsernameOverride,
                        focusCommentOnAppear: ctx.focusCommentOnAppear,
                        suppressHostChrome: $suppressHostChrome,
                        onOpenCurrentUserLog: { game in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                mode = .editor(game, startsWithExistingLog: true)
                            }
                        },
                        embeddedOverlay: true,
                        hostedInOverlay: true
                    )
                case .editor(let game, let startsWithExistingLog):
                    GameDetailView(
                        game: game,
                        compactOverlay: true,
                        hostedInOverlay: true,
                        suppressHostChrome: $suppressHostChrome,
                        onRequestClose: onClose,
                        externalDismissRequestID: editorDismissRequestID,
                        startWithExistingLog: startsWithExistingLog
                    )
                }
            }
            .preferredColorScheme(ColorTheme.preferredScheme)
            .frame(width: min(UIScreen.main.bounds.width - 24, 394),
                   height: min(UIScreen.main.bounds.height - 40, 860))
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(ColorTheme.background)
                    LinearGradient(
                        colors: [hostAccent.opacity(0.10), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(hostAccent.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topLeading) {
                if !suppressHostChrome {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(modeTitle)
                            .font(.caption2.weight(.black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.56)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                        if case .preview(let ctx) = mode {
                            Text(formattedStatus(ctx.gameLog.status))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.42)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                    }
                    .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !suppressHostChrome {
                    Button {
                        switch mode {
                        case .preview:
                            onClose()
                        case .editor:
                            editorDismissRequestID += 1
                        }
                    } label: {
                        OverlayCloseButton()
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
