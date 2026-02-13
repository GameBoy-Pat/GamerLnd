// ListsService.swift
// Firestore CRUD for lists + items.
// Aligns with rules:
// • Lists types: 'regular' | 'ranked' | 'tiered'
// • Item create requires game_id, game_name, (cover_image_id optional), added_at timestamp
// • order/tier are only updated (not required on create)

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class ListsService {
    static let shared = ListsService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Read

    func fetchLists(forUserId uid: String, completion: @escaping ([UserList]) -> Void) {
        db.collection("lists")
            .whereField("owner_id", isEqualTo: uid)
            .order(by: "updated_at", descending: true)
            .getDocuments { snap, _ in
                let lists: [UserList] = (snap?.documents ?? []).compactMap {
                    UserList(id: $0.documentID, data: $0.data())
                }
                completion(lists)
            }
    }

    // MARK: - Create

    func createList(ownerId: String,
                    title: String,
                    description: String?,
                    type: ListType,
                    isPublic: Bool,
                    completion: @escaping (Result<UserList, Error>) -> Void) {
        createList(ownerId: ownerId,
                   title: title,
                   description: description,
                   type: type,
                   isPublic: isPublic,
                   tierLabels: nil,
                   tierColors: nil,
                   completion: completion)
    }

    // Overload to accept optional tier metadata
    func createList(ownerId: String,
                    title: String,
                    description: String?,
                    type: ListType,
                    isPublic: Bool,
                    tierLabels: [String]?,
                    tierColors: [String]?,
                    completion: @escaping (Result<UserList, Error>) -> Void) {
        guard !ownerId.isEmpty else { return }
        let id = UUID().uuidString
        let now = Timestamp(date: Date())

        var data: [String: Any] = [
            "id": id,
            "owner_id": ownerId,
            "title": title,
            "description": description ?? "",
            "type": type.rawValue,
            "is_public": isPublic,
            "created_at": now,
            "updated_at": now,
            "item_count": 0
        ]

        if type == .tiered {
            data["tier_labels"] = tierLabels ?? ["S", "A", "B", "C", "D"]
            data["tier_colors"] = tierColors ?? ["", "", "", "", ""]
        }

        db.collection("lists").document(id).setData(data, merge: false) { err in
            if let err = err { completion(.failure(err)); return }
            completion(.success(UserList(id: id,
                                         ownerId: ownerId,
                                         title: title,
                                         description: description ?? "",
                                         type: type,
                                         isPublic: isPublic,
                                         createdAt: now,
                                         updatedAt: now,
                                         itemCount: 0,
                                         tierLabels: data["tier_labels"] as? [String],
                                         tierColors: data["tier_colors"] as? [String])))
        }
    }

    // MARK: - Update meta

    func updateListMeta(listId: String,
                        title: String,
                        description: String?,
                        isPublic: Bool? = nil,
                        type: ListType? = nil,
                        tierLabels: [String]? = nil,
                        tierColors: [String]? = nil,
                        completion: (() -> Void)? = nil) {
        var patch: [String: Any] = [
            "title": title,
            "description": description ?? "",
            "updated_at": Timestamp(date: Date())
        ]
        if let isPublic = isPublic { patch["is_public"] = isPublic }
        if let type = type { patch["type"] = type.rawValue }
        if let labels = tierLabels { patch["tier_labels"] = labels }
        if let colors = tierColors { patch["tier_colors"] = colors }

        db.collection("lists").document(listId).setData(patch, merge: true) { _ in completion?() }
    }

    // MARK: - Items

    func addItems(listId: String, items: [UserListItem], completion: (() -> Void)? = nil) {
        let batch = db.batch()
        let listRef = db.collection("lists").document(listId)

        for it in items {
            let ref = listRef.collection("items").document(it.id)
            var payload: [String: Any] = [
                "id": it.id,
                "list_id": listId,
                "game_id": it.gameId,
                "game_name": it.gameName,
                "cover_image_id": it.coverImageId as Any,
                "added_at": FieldValue.serverTimestamp()
            ]
            if let ord = it.order { payload["order"] = ord }
            if let tier = it.tier { payload["tier"] = tier }
            batch.setData(payload, forDocument: ref, merge: false)
        }

        batch.updateData([
            "updated_at": Timestamp(date: Date()),
            "item_count": FieldValue.increment(Int64(items.count))
        ], forDocument: listRef)

        batch.commit { _ in completion?() }
    }

    func removeItems(listId: String, itemIds: [String], completion: (() -> Void)? = nil) {
        let batch = db.batch()
        let listRef = db.collection("lists").document(listId)
        for iid in itemIds {
            batch.deleteDocument(listRef.collection("items").document(iid))
        }
        batch.updateData([
            "updated_at": Timestamp(date: Date()),
            "item_count": FieldValue.increment(Int64(-itemIds.count))
        ], forDocument: listRef)
        batch.commit { _ in completion?() }
    }

    /// Update "order" for ranked lists (maps from your app's rank).
    func updateOrders(listId: String, updates: [(id: String, order: Int)], completion: (() -> Void)? = nil) {
        let batch = db.batch()
        let listRef = db.collection("lists").document(listId)
        for u in updates {
            batch.setData(["order": u.order], forDocument: listRef.collection("items").document(u.id), merge: true)
        }
        batch.updateData(["updated_at": Timestamp(date: Date())], forDocument: listRef)
        batch.commit { _ in completion?() }
    }

    /// Back-compat alias if any caller still references updateRanks(...)
    func updateRanks(listId: String, updates: [(id: String, order: Int)], completion: (() -> Void)? = nil) {
        updateOrders(listId: listId, updates: updates, completion: completion)
    }

    /// Update order + optional tier string for tiered lists.
    func updateTierPositions(listId: String,
                             items: [(id: String, order: Int, tier: String?)],
                             completion: (() -> Void)? = nil) {
        let batch = db.batch()
        let listRef = db.collection("lists").document(listId)
        for it in items {
            var patch: [String: Any] = ["order": it.order]
            if let t = it.tier { patch["tier"] = t }
            batch.setData(patch, forDocument: listRef.collection("items").document(it.id), merge: true)
        }
        batch.updateData(["updated_at": Timestamp(date: Date())], forDocument: listRef)
        batch.commit { _ in completion?() }
    }
}
