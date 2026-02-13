// AppLinks.swift
// Minimal helpers so existing share/deeplink references compile safely.
// You can swap these to real universal links later.

import Foundation

struct AppLinks {
    static func profileURL(uid: String) -> URL {
        URL(string: "gamerlnd://u/\(uid)")!
    }

    static func gameURL(gameId: Int) -> URL {
        URL(string: "gamerlnd://g/\(gameId)")!
    }

    static func logURL(logId: String) -> URL {
        URL(string: "gamerlnd://l/\(logId)")!
    }
}
