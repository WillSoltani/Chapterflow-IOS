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

        self.healthRecorder = healthRecorder
        client = APIClient(
            config: config,
            tokenProvider: tokenProvider,
            session: session,
            observer: observer
        )
    }
}
