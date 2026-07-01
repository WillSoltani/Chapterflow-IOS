import Foundation
import SwiftUI

/// A destination that can be pushed onto a `Router`'s navigation stack.
///
/// Concrete route enums (`HomeRoute`, `LibraryRoute`, …) live in the feature
/// packages and conform to `Routed`; `CoreKit` only provides the primitive so
/// the navigation plumbing is shared.
public protocol Routed: Hashable, Sendable {}

/// An `@Observable` owner of a `NavigationPath`, driving one `NavigationStack`.
///
/// Views bind `path` to a `NavigationStack(path:)` and switch on the pushed
/// `Routed` values in a `navigationDestination`. The push/pop helpers keep call
/// sites free of `NavigationPath` bookkeeping.
@MainActor
@Observable
public final class Router {
    public var path: NavigationPath

    public init(path: NavigationPath = NavigationPath()) {
        self.path = path
    }

    /// Number of destinations currently on the stack.
    public var depth: Int { path.count }

    /// Whether the stack is at its root.
    public var isAtRoot: Bool { path.isEmpty }

    /// Pushes a route onto the stack.
    public func push<R: Routed>(_ route: R) {
        path.append(route)
    }

    /// Pops the top destination, if any.
    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Pops all destinations back to the root.
    public func popToRoot() {
        guard !path.isEmpty else { return }
        path.removeLast(path.count)
    }
}
