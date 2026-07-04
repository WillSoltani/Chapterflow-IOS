// MARK: - Share event endpoints

public extension Endpoints {

    /// `POST /book/me/share-events` — log that the user shared a card.
    ///
    /// - Parameters:
    ///   - cardType: The kind of card shared (`chapter`, `badge`, `streak`, `book`).
    ///   - destination: The share destination (e.g. `instagram`, `other`).
    static func postShareEvent(cardType: String, destination: String) throws -> Endpoint {
        struct Body: Encodable {
            let cardType: String
            let destination: String
        }
        return try Endpoint(
            method: .post,
            path: "/book/me/share-events",
            body: Body(cardType: cardType, destination: destination)
        )
    }
}
