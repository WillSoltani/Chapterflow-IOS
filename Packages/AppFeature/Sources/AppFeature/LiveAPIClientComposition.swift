import CoreKit
import Foundation
import Networking

/// Owns the one live API client and its bounded, privacy-safe observer graph.
///
/// Tests can inject a URL session and crash reporter without changing the live
/// composition used by `AppModel`.
struct LiveAPIClientComposition {
    let client: APIClient
    let healthRecorder: APIObservationHealthRecorder
    let clientFactory: LiveAPIClientFactory

    init(
        config: AppConfig,
        tokenProvider: any TokenProviding,
        session: URLSession = .shared,
        reporter: any CrashReporter,
        initialSessionState: APIObservationSessionState
    ) {
        let healthRecorder = APIObservationHealthRecorder(
            initialSessionState: initialSessionState
        )
        let observer = CompositeAPIClientObserver([
            healthRecorder,
            CrashBreadcrumbAPIObserver(reporter: reporter),
        ])

        let clientFactory = LiveAPIClientFactory(
            config: config,
            session: session,
            observer: observer
        )
        self.healthRecorder = healthRecorder
        self.clientFactory = clientFactory
        client = clientFactory.make(tokenProvider: tokenProvider)
    }
}

/// Recreates the exact live networking stack with an account-bound token
/// provider while sharing the process-long, privacy-safe observer graph.
struct LiveAPIClientFactory: Sendable {
    let config: AppConfig
    let session: URLSession
    let observer: any APIClientObserver

    func make(tokenProvider: any TokenProviding) -> APIClient {
        APIClient(
            config: config,
            tokenProvider: tokenProvider,
            session: session,
            observer: observer
        )
    }
}
