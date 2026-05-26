import Foundation
import FirebaseAuth
import UIKit

enum SearchReportReason: String, CaseIterable, Identifiable {
    case notRelevant = "Not relevant to my search"
    case badEntry = "Bad / duplicate / fan-made entry"
    case misleading = "Broken or misleading metadata"
    case other = "Other"

    var id: String { rawValue }
}

struct SearchResultReportContext {
    let query: String
    let gameId: Int
    let gameName: String
    let resultIndex: Int
    let surface: String
}

enum SearchReportService {
    static func submit(context: SearchResultReportContext, reason: SearchReportReason, notes: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedQuery = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUser = Auth.auth().currentUser
        let reporterLine: String = {
            if let email = currentUser?.email, !email.isEmpty {
                return email
            }
            return "Unknown"
        }()
        let bodyLines = [
            "Search Result Report",
            "",
            "Game: \(context.gameName)",
            "Game ID: \(context.gameId)",
            "Search Query: \(trimmedQuery)",
            "Reason: \(reason.rawValue)",
            "Surface: \(context.surface)",
            "Result Index: \(context.resultIndex)",
            "Reporter: \(reporterLine)",
            "",
            "Notes:",
            trimmedNotes.isEmpty ? "None provided" : trimmedNotes
        ]
        let subject = "GamerLnd Search Result Report: \(context.gameName)"
        let body = bodyLines.joined(separator: "\n")

        guard
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "mailto:programming.pf@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)")
        else {
            completion(.failure(NSError(domain: "SearchReportService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not prepare report email."])))
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { opened in
                if opened {
                    RewardService.shared.recordFlaggedGame(gameId: context.gameId)
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(domain: "SearchReportService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mail app is unavailable."])))
                }
            }
        }
    }
}
