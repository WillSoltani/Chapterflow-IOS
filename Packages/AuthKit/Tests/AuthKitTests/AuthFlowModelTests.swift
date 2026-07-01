import Testing
@testable import AuthKit
import CoreKit
import Foundation

// MARK: - PasswordStrength Tests

@Suite("PasswordStrength")
struct PasswordStrengthTests {

    // MARK: evaluate(_:)

    @Test("empty password scores 0")
    func emptyPassword() {
        let s = PasswordStrength.evaluate("")
        #expect(s.score == 0)
    }

    @Test("very short password scores 0")
    func veryShortPassword() {
        // Under 8 chars, no uppercase, no number, no symbol → 0
        let s = PasswordStrength.evaluate("abc")
        #expect(s.score == 0)
    }

    @Test("8-char lowercase-only scores 1")
    func eightCharLowercase() {
        let s = PasswordStrength.evaluate("abcdefgh")
        #expect(s.score == 1)
    }

    @Test("8-char with uppercase scores 2 (Fair)")
    func eightCharWithUppercase() {
        let s = PasswordStrength.evaluate("Abcdefgh")
        #expect(s.score == 2)
    }

    @Test("8-char with uppercase and digit scores 3 (Good)")
    func eightCharWithUppercaseAndDigit() {
        let s = PasswordStrength.evaluate("Abcdefg1")
        #expect(s.score == 3)
    }

    @Test("strong password with all criteria scores 4")
    func strongPassword() {
        let s = PasswordStrength.evaluate("Hunter2!")
        #expect(s.score == 4)
    }

    @Test("long lowercase-only still only gets length point")
    func longLowercase() {
        let s = PasswordStrength.evaluate("abcdefghijklmnop")
        #expect(s.score == 1)
    }

    // MARK: label

    @Test("score 0 label is Weak")
    func labelWeak0() { #expect(PasswordStrength(score: 0).label == "Weak") }

    @Test("score 1 label is Weak")
    func labelWeak1() { #expect(PasswordStrength(score: 1).label == "Weak") }

    @Test("score 2 label is Fair")
    func labelFair() { #expect(PasswordStrength(score: 2).label == "Fair") }

    @Test("score 3 label is Good")
    func labelGood() { #expect(PasswordStrength(score: 3).label == "Good") }

    @Test("score 4 label is Strong")
    func labelStrong() { #expect(PasswordStrength(score: 4).label == "Strong") }

    // MARK: fractionComplete

    @Test("score 0 fraction is 0.0")
    func fraction0() { #expect(PasswordStrength(score: 0).fractionComplete == 0.0) }

    @Test("score 2 fraction is 0.5")
    func fraction2() { #expect(PasswordStrength(score: 2).fractionComplete == 0.5) }

    @Test("score 4 fraction is 1.0")
    func fraction4() { #expect(PasswordStrength(score: 4).fractionComplete == 1.0) }

    @Test("negative score clamps to 0.0")
    func fractionNegative() { #expect(PasswordStrength(score: -1).fractionComplete == 0.0) }

    @Test("score above 4 clamps to 1.0")
    func fractionOverflow() { #expect(PasswordStrength(score: 10).fractionComplete == 1.0) }
}

// MARK: - Email Validation Tests

/// All tests are `@MainActor` because `AuthFlowModel` and `AuthService` are
/// both `@MainActor`-isolated.
@Suite("AuthFlowModel.isValidEmail")
@MainActor
struct EmailValidationTests {

    private func makeModel() -> AuthFlowModel {
        let config = AppConfig(
            apiBaseURL: "https://test.example.com",
            cognitoRegion: "us-east-1",
            cognitoUserPoolID: "us-east-1_test",
            cognitoClientID: "testClientId"
        )
        return AuthFlowModel(authService: AuthService(config: config))
    }

    @Test("valid plain email returns true")
    func validSimpleEmail() {
        #expect(makeModel().isValidEmail("user@example.com"))
    }

    @Test("valid email with subdomain returns true")
    func validSubdomainEmail() {
        #expect(makeModel().isValidEmail("user@mail.example.co.uk"))
    }

    @Test("valid email with plus sign returns true")
    func validPlusEmail() {
        #expect(makeModel().isValidEmail("user+tag@example.com"))
    }

    @Test("missing @ returns false")
    func missingAt() {
        #expect(!makeModel().isValidEmail("userexample.com"))
    }

    @Test("missing domain returns false")
    func missingDomain() {
        #expect(!makeModel().isValidEmail("user@"))
    }

    @Test("missing TLD returns false")
    func missingTLD() {
        #expect(!makeModel().isValidEmail("user@example"))
    }

    @Test("empty string returns false")
    func emptyString() {
        #expect(!makeModel().isValidEmail(""))
    }

    @Test("spaces return false")
    func withSpaces() {
        #expect(!makeModel().isValidEmail("user @example.com"))
    }

    @Test("email with dots in local part returns true")
    func dotsInLocal() {
        #expect(makeModel().isValidEmail("first.last@example.com"))
    }
}
