import Testing
import Foundation
@testable import RichNotificationCore

@Suite("AttachmentPreparation")
struct AttachmentPreparationTests {

    // MARK: - prepare(from:)

    @Test("prepare returns nil when payload has no imageURL")
    func prepareNilWhenNoImage() {
        let payload = PushPayload(
            typeRaw: "badge_earned",
            imageURL: nil,
            badgeKey: nil, badgeName: nil, bookId: nil, chapterNumber: nil, deepLink: nil
        )
        #expect(AttachmentPreparation.prepare(from: payload) == nil)
    }

    @Test("prepare returns preparation when payload has imageURL")
    func prepareReturnsPrepWhenImagePresent() throws {
        let url = try #require(URL(string: "https://cdn.chapterflow.com/badges/first.png"))
        let payload = PushPayload(
            typeRaw: "badge_earned",
            imageURL: url,
            badgeKey: "first", badgeName: "First", bookId: nil, chapterNumber: nil, deepLink: nil
        )
        let prep = try #require(AttachmentPreparation.prepare(from: payload))
        #expect(prep.sourceURL == url)
    }

    // MARK: - Filename inference

    @Test("JPEG extension yields .jpeg filename")
    func jpegFilename() throws {
        let url = try #require(URL(string: "https://cdn.example.com/image.jpeg"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.suggestedFilename == "cf-notification-image.jpeg")
    }

    @Test("JPG extension yields .jpg filename")
    func jpgFilename() throws {
        let url = try #require(URL(string: "https://cdn.example.com/image.jpg"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.suggestedFilename == "cf-notification-image.jpg")
    }

    @Test("PNG extension yields .png filename")
    func pngFilename() throws {
        let url = try #require(URL(string: "https://cdn.example.com/badge.png"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.suggestedFilename == "cf-notification-image.png")
    }

    @Test("GIF extension yields .gif filename")
    func gifFilename() throws {
        let url = try #require(URL(string: "https://cdn.example.com/anim.gif"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.suggestedFilename == "cf-notification-image.gif")
    }

    @Test("URL without extension yields .jpg fallback filename")
    func noExtensionFallbackFilename() throws {
        let url = try #require(URL(string: "https://cdn.example.com/badge-image"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.suggestedFilename == "cf-notification-image.jpg")
    }

    // MARK: - UTI inference

    @Test("JPG/JPEG extension yields public.jpeg UTI")
    func jpegUTI() throws {
        let url = try #require(URL(string: "https://cdn.example.com/img.jpg"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.uniformTypeIdentifier == "public.jpeg")
    }

    @Test("PNG extension yields public.png UTI")
    func pngUTI() throws {
        let url = try #require(URL(string: "https://cdn.example.com/img.png"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.uniformTypeIdentifier == "public.png")
    }

    @Test("GIF extension yields com.compuserve.gif UTI")
    func gifUTI() throws {
        let url = try #require(URL(string: "https://cdn.example.com/anim.gif"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.uniformTypeIdentifier == "com.compuserve.gif")
    }

    @Test("WEBP extension yields org.webmproject.webp UTI")
    func webpUTI() throws {
        let url = try #require(URL(string: "https://cdn.example.com/img.webp"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.uniformTypeIdentifier == "org.webmproject.webp")
    }

    @Test("unknown extension yields nil UTI")
    func unknownUTI() throws {
        let url = try #require(URL(string: "https://cdn.example.com/img.bmp"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.uniformTypeIdentifier == nil)
    }

    @Test("no extension yields nil UTI and fallback filename")
    func noExtensionUTI() throws {
        let url = try #require(URL(string: "https://cdn.example.com/image"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.uniformTypeIdentifier == nil)
        #expect(prep.suggestedFilename == "cf-notification-image.jpg")
    }

    @Test("sourceURL is preserved exactly")
    func sourceURLPreserved() throws {
        let url = try #require(URL(string: "https://cdn.example.com/img.png"))
        let prep = AttachmentPreparation(sourceURL: url)
        #expect(prep.sourceURL == url)
    }
}
