import Testing
import Foundation
@testable import AuthKit
import CoreKit

@Suite("PasswordStrength")
struct PasswordStrengthTests {

    @Test("weak for passwords under 6 characters")
    func weakShort() {
        #expect(PasswordStrength.evaluate("ab").level == .weak)
        #expect(PasswordStrength.evaluate("abcde").level == .weak)
    }

    @Test("fair for 6+ character passwords with limited complexity")
    func fairMedium() {
        #expect(PasswordStrength.evaluate("abcdef").level == .fair)
        #expect(PasswordStrength.evaluate("abcdefg").level == .fair)
    }

    @Test("strong for 8+ characters with 2 or more character types")
    func strongComplex() {
        #expect(PasswordStrength.evaluate("Abcd1234").level == .strong)
        #expect(PasswordStrength.evaluate("abcd1234").level == .strong)
    }

    @Test("very strong for 12+ characters with 3 or more character types")
    func veryStrongLong() {
        #expect(PasswordStrength.evaluate("Abcdefg12345").level == .veryStrong)
        #expect(PasswordStrength.evaluate("Abcd1234!@#$").level == .veryStrong)
    }

    @Test("fraction progresses from weak to very strong")
    func fractionProgresses() {
        #expect(PasswordStrength(level: .weak).fraction < PasswordStrength(level: .fair).fraction)
        #expect(PasswordStrength(level: .fair).fraction < PasswordStrength(level: .strong).fraction)
        #expect(PasswordStrength(level: .strong).fraction < PasswordStrength(level: .veryStrong).fraction)
        #expect(PasswordStrength(level: .veryStrong).fraction == 1.0)
    }
}

@Suite("Email Validation")
struct EmailValidationTests {

    @Test("accepts well-formed email addresses")
    func validEmails() {
        #expect(AuthFlowModel.isValidEmail("user@example.com"))
        #expect(AuthFlowModel.isValidEmail("user+tag@sub.example.co.uk"))
        #expect(AuthFlowModel.isValidEmail("User.Name@Example.ORG"))
    }

    @Test("rejects email without @ symbol")
    func missingAt() {
        #expect(!AuthFlowModel.isValidEmail("userexample.com"))
    }

    @Test("rejects email without TLD")
    func missingTLD() {
        #expect(!AuthFlowModel.isValidEmail("user@example"))
    }

    @Test("rejects email with single-character TLD")
    func shortTLD() {
        #expect(!AuthFlowModel.isValidEmail("user@example.c"))
    }

    @Test("rejects empty string")
    func emptyString() {
        #expect(!AuthFlowModel.isValidEmail(""))
    }

    @Test("rejects whitespace-only string")
    func whitespace() {
        #expect(!AuthFlowModel.isValidEmail("   "))
    }
}
