public enum PoolError : ErrorProtocol {
    case tooBusy, empty, timeout, maxErrorDurationExeceeded, maxWaitDurationExceeded, maxUnavailableDurationExceeded
}

public protocol Pool {
    associatedtype Poolable
    func borrow () -> Poolable?
    func takeBack (poolable: Poolable)
    func with (handler: (poolable: Poolable) throws -> Any?) throws
}

public protocol PoolConfiguration {
    var maxErrorDuration: Duration { get }
    var retryDelay: Duration { get }
    var connectionWait: Duration { get }
    var maxReconnectDuration: Duration { get }
}
