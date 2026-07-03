import Foundation
import SwiftData

// MARK: - PendingCommitmentUpload

/// An offline upload ticket for a commitment that could not be synced immediately.
///
/// Created when `POST /book/me/commitments` or
/// `PATCH /book/me/commitments/{id}` fails with `.offline`.
/// The sync engine retries these when connectivity is restored.
@Model
public final class PendingCommitmentUpload {
    @Attribute(.unique) public var uploadId: String
    /// The local commitment ID (UUID assigned at creation time before the server assigns one).
    public var localCommitmentId: String
    /// `"create"` or `"update"`.
    public var operation: String
    /// For update operations, the server-assigned commitment ID. Nil for creates.
    public var serverCommitmentId: String?
    /// JSON body for the request.
    public var requestJSON: String
    public var retryCount: Int
    public var nextRetryAt: Date
    public var createdAt: Date

    public init(
        uploadId: String = UUID().uuidString,
        localCommitmentId: String,
        operation: String,
        serverCommitmentId: String? = nil,
        requestJSON: String,
        retryCount: Int = 0,
        nextRetryAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.uploadId = uploadId
        self.localCommitmentId = localCommitmentId
        self.operation = operation
        self.serverCommitmentId = serverCommitmentId
        self.requestJSON = requestJSON
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.createdAt = createdAt
    }
}
