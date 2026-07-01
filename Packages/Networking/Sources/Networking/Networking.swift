/// Namespace for the Networking module.
///
/// The public surface of this package is the ``APIClient`` actor (and its
/// ``APIClientProtocol`` abstraction), the ``Endpoint`` value type plus the
/// ``Endpoints`` factory, the ``TokenProviding`` auth hook, ``JSONCoding`` for
/// the shared encoder/decoder, and ``MockAPIClient`` for testing features
/// without a live network.
public enum Networking {
    /// The name of this module. Useful as a smoke-test symbol.
    public static let moduleName = "Networking"
}
