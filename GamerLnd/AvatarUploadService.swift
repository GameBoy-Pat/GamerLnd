import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

enum AvatarUploadService {
    static func upload(userId: String, imageData: Data, completion: @escaping (String?, Error?) -> Void) {
        let prepared = preparedAvatarPayload(from: imageData)
        let ref = Storage.storage().reference().child("avatars/\(userId).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(prepared.jpegData, metadata: meta) { _, error in
            if let error = error {
                fallbackToInlineAvatar(userId: userId, imageData: prepared.jpegData, underlyingError: error, completion: completion)
                return
            }

            ref.downloadURL { url, downloadError in
                if let url = url {
                    persistPhotoURLIfNeeded(url.absoluteString)
                    completion(url.absoluteString, nil)
                } else if let downloadError = downloadError {
                    fallbackToInlineAvatar(userId: userId, imageData: prepared.jpegData, underlyingError: downloadError, completion: completion)
                } else {
                    fallbackToInlineAvatar(
                        userId: userId,
                        imageData: prepared.jpegData,
                        underlyingError: NSError(domain: "AvatarUploadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch uploaded avatar URL."]),
                        completion: completion
                    )
                }
            }
        }
    }

    private static func preparedAvatarPayload(from data: Data) -> (jpegData: Data, pixelSize: CGSize) {
        let maxDimension: CGFloat = 256
        let fallbackJPEG = UIImage(data: data)?.jpegData(compressionQuality: 0.5) ?? data

        guard let image = UIImage(data: data) else {
            return (fallbackJPEG, .zero)
        }

        let originalSize = image.size
        let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        let compressed = resized.jpegData(compressionQuality: 0.5)
            ?? resized.jpegData(compressionQuality: 0.35)
            ?? fallbackJPEG

        return (compressed, targetSize)
    }

    private static func fallbackToInlineAvatar(userId: String, imageData: Data, underlyingError: Error, completion: @escaping (String?, Error?) -> Void) {
        let inlineURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let payload: [String: Any] = [
            "avatar_url": inlineURL,
            "profile_picture_url": inlineURL,
            "updated_at": Timestamp(date: Date())
        ]

        Firestore.firestore().collection("users").document(userId).setData(payload, merge: true) { error in
            if let error = error {
                completion(nil, error)
                return
            }
            persistPhotoURLIfNeeded(inlineURL)
            completion(inlineURL, nil)
        }
    }

    private static func persistPhotoURLIfNeeded(_ value: String) {
        guard let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest() else { return }
        changeRequest.photoURL = URL(string: value)
        changeRequest.commitChanges(completion: nil)
    }
}
