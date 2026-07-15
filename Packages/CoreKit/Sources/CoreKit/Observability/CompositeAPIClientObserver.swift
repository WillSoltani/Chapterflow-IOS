/// Synchronously fans one closed API observation out to bounded child observers.
///
/// Child order is stable. The observer boundary is nonthrowing, so a child that
/// rejects an event or traps its own internal storage failure cannot affect the
/// remaining children or the API operation that produced the event.
public struct CompositeAPIClientObserver: APIClientObserver {
    private let observers: [any APIClientObserver]

    public init(_ observers: [any APIClientObserver]) {
        self.observers = observers
    }

    public func captureContext() -> APIObservationContext {
        APIObservationContext(childContexts: observers.map { $0.captureContext() })
    }

    public func record(_ event: APIRequestObservation) {
        for observer in observers {
            observer.record(event)
        }
    }

    public func record(_ event: APIRequestObservation, context: APIObservationContext) {
        let contexts = context.childContexts
        for (index, observer) in observers.enumerated() {
            let childContext: APIObservationContext
            if let contexts, contexts.indices.contains(index) {
                childContext = contexts[index]
            } else {
                // Fail closed for context-sensitive children. Context-free
                // observers use the protocol default and still receive the event.
                childContext = APIObservationContext()
            }
            observer.record(event, context: childContext)
        }
    }
}
