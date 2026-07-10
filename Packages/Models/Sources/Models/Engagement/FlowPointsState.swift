/// Current flow-points balance for the user.
///
/// Returned by `GET /book/me/flow-points`. P5.1 used only `balance` from
/// the dashboard aggregate; P5.4 fetches this endpoint directly for the
/// full ledger.
public struct FlowPointsState: Codable, Sendable, Equatable {
    public let balance: Int

    public init(balance: Int) {
        self.balance = balance
    }
}

/// Top-level response wrapper for `GET /book/me/flow-points`.
///
/// `ledger` and `equippedCosmetics` are optional because early clients
/// (P5.1) called this endpoint without needing the full payload and the
/// server may gate ledger data behind a query parameter.
public struct FlowPointsResponse: Codable, Sendable {
    public let balance: Int
    /// Transaction history, oldest-first. `nil` when the server omits it.
    public let ledger: [FlowLedgerEntry]?
    /// Which cosmetics the user has equipped. `nil` when the server omits it.
    public let equippedCosmetics: EquippedCosmetics?

    public init(
        balance: Int,
        ledger: [FlowLedgerEntry]? = nil,
        equippedCosmetics: EquippedCosmetics? = nil
    ) {
        self.balance = balance
        self.ledger = ledger
        self.equippedCosmetics = equippedCosmetics
    }

    // MARK: Tolerant decoding (contract reconciliation)
    //
    // The deployed /book/me/flow-points nests the balance under
    // `summary.balance` and keys the history `recentTransactions` (entries:
    // {transactionId, direction, amount, sourceType, title, subtitle, …}).
    // The canonical flat {balance, ledger} shape (caches/fixtures) also
    // decodes; encoding stays canonical.

    private enum CodingKeys: String, CodingKey {
        case balance, ledger, equippedCosmetics
        case summary, recentTransactions
    }

    private enum SummaryK: String, CodingKey { case balance }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let flat = container.decodeFirst(Int.self, keys: [.balance]) {
            self.balance = flat
        } else if let summary = try? container.nestedContainer(
            keyedBy: SummaryK.self, forKey: .summary),
            let nested = summary.decodeFirst(Int.self, keys: [.balance]) {
            self.balance = nested
        } else {
            self.balance = 0
        }
        // Ledger is optional; when present decode lossily so one bad entry
        // doesn't corrupt the whole response.
        if container.contains(.ledger) {
            self.ledger = try container.decodeLossy(FlowLedgerEntry.self, forKey: .ledger)
        } else if container.contains(.recentTransactions) {
            self.ledger = try container.decodeLossy(
                FlowLedgerEntry.self, forKey: .recentTransactions)
        } else {
            self.ledger = nil
        }
        self.equippedCosmetics = try? container.decodeIfPresent(
            EquippedCosmetics.self, forKey: .equippedCosmetics) ?? nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(balance, forKey: .balance)
        try container.encodeIfPresent(ledger, forKey: .ledger)
        try container.encodeIfPresent(equippedCosmetics, forKey: .equippedCosmetics)
    }
}
