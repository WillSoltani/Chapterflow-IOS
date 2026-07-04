// MARK: - Reflection endpoints

public extension Endpoints {

    /// `GET /book/me/reflections/{bookId}/{n}` → `{ reflections: [...] }`.
    static func getReflections(bookId: String, chapterN: Int) -> Endpoint {
        Endpoint(method: .get, path: "/book/me/reflections/\(bookId)/\(chapterN)", requiresAuth: true)
    }

    /// `POST /book/me/reflections/{bookId}/{n}` → `{ reflection: {...} }`.
    static func postReflection(bookId: String, chapterN: Int, text: String) throws -> Endpoint {
        struct Body: Encodable { let text: String }
        return try Endpoint(
            method: .post,
            path: "/book/me/reflections/\(bookId)/\(chapterN)",
            body: Body(text: text)
        )
    }

    /// `POST /book/me/reflections/{bookId}/{n}/feedback` → `{ feedbackText: String }`.
    static func requestReflectionFeedback(
        bookId: String,
        chapterN: Int,
        reflectionId: String
    ) throws -> Endpoint {
        struct Body: Encodable { let reflectionId: String }
        return try Endpoint(
            method: .post,
            path: "/book/me/reflections/\(bookId)/\(chapterN)/feedback",
            body: Body(reflectionId: reflectionId)
        )
    }
}
