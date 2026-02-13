// ListModels.swift
// Models for user lists (align with security rules: types 'regular', 'ranked', 'tiered').

import Foundation
import FirebaseFirestore

enum ListType: String, Codable, CaseIterable {
    case regular
    case ranked
    case tiered

    var titleText: String {
        switch self {
        case .regular: return "Collection"
        case .ranked:  return "Ranked"
        case .tiered:  return "Tiered"
        }
    }
}

struct UserList: Identifiable, Hashable, Codable {
    let id: String
    let ownerId: String
    var title: String
    var description: String
    var type: ListType
    var isPublic: Bool
    var createdAt: Timestamp
    var updatedAt: Timestamp
    var itemCount: Int

    // Optional tier metadata (only for tiered lists)
    var tierLabels: [String]?
    var tierColors: [String]?

    init(id: String,
         ownerId: String,
         title: String,
         description: String,
         type: ListType,
         isPublic: Bool,
         createdAt: Timestamp,
         updatedAt: Timestamp,
         itemCount: Int,
         tierLabels: [String]? = nil,
         tierColors: [String]? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.description = description
        self.type = type
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.itemCount = itemCount
        self.tierLabels = tierLabels
        self.tierColors = tierColors
    }

    init?(id: String, data: [String: Any]) {
        guard
            let ownerId = data["owner_id"] as? String,
            let title = data["title"] as? String,
            let description = data["description"] as? String,
            let typeStr = data["type"] as? String,
            let type = ListType(rawValue: typeStr),
            let isPublic = data["is_public"] as? Bool,
            let createdAt = data["created_at"] as? Timestamp,
            let updatedAt = data["updated_at"] as? Timestamp,
            let itemCount = (data["item_count"] as? Int) ?? (data["item_count"] as? NSNumber)?.intValue
        else { return nil }

        self.init(
            id: id,
            ownerId: ownerId,
            title: title,
            description: description,
            type: type,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt,
            itemCount: itemCount,
            tierLabels: data["tier_labels"] as? [String],
            tierColors: data["tier_colors"] as? [String]
        )
    }
}
