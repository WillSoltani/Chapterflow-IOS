/// Current flow-points balance for the user.
///
/// Returned by `GET /book/me/flow-points`. The full ledger is fetched in P5.4;
/// P5.1 uses only the `balance` field from the dashboard aggregate.
public struct FlowPointsState: Codable, Sendable, Equatable {
    public let balance: Int

    public init(balance: Int) {
        self.balance = balance
    }
}

/// Top-level response wrapper for `GET /book/me/flow-points`.
public struct FlowPointsResponse: Codable, Sendable {
    public let balance: Int

    public init(balance: Int) {
        self.balance = balance
    }
}
