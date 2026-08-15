// FeatherCore must build on Linux so its tests can run in CI and on non-Mac dev
// hosts. Combine does not exist there, so provide the two names the core uses.
#if canImport(Combine)
@_exported import Combine
#else
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
