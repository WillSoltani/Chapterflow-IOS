@preconcurrency import Amplify
@preconcurrency import AWSPluginsCore
import AWSCognitoAuthPlugin
import CoreKit

/// One-time Amplify configuration. Calling `configure` after the first
/// successful call is a no-op, making it safe to call from tests.
@MainActor
enum AmplifyConfigurator {
    private static var configured = false

    static func configure(with config: AppConfig) throws {
        guard !configured else { return }

        // Build the awsCognitoAuthPlugin configuration that Amplify expects.
        // This matches the structure of an amplifyconfiguration.json User-Pool-only setup.
        let pluginConfig: JSONValue = .object([
            "UserAgent": .string("aws-amplify/cli"),
            "Version": .string("0.1.0"),
            "IdentityManager": .object(["Default": .object([:])]),
            "CognitoUserPool": .object([
                "Default": .object([
                    "PoolId": .string(config.cognitoUserPoolID),
                    "AppClientId": .string(config.cognitoClientID),
                    "Region": .string(config.cognitoRegion),
                ]),
            ]),
            "Auth": .object([
                "Default": .object([
                    "authenticationFlowType": .string("USER_SRP_AUTH"),
                ]),
            ]),
        ])

        let authConfig = AuthCategoryConfiguration(
            plugins: ["awsCognitoAuthPlugin": pluginConfig]
        )
        let amplifyConfig = AmplifyConfiguration(auth: authConfig)

        try Amplify.add(plugin: AWSCognitoAuthPlugin())
        try Amplify.configure(amplifyConfig)
        configured = true
    }
}
