import C7
import Venice
import TCP

public class ConnectionPool<PoolConnection : Connection where PoolConnection : AnyObject>  : Pool {

    
    var configuration : PoolConfiguration
    
    private var active = [PoolConnection]()
    private var lent = [PoolConnection]()
    private var idle = [PoolConnection]()
    private var suspect = [PoolConnection]()
    private var pendingRetry = [PoolConnection]()
    
    private var errorDurations = [Int: Duration]()
    private var connectionErrors = [Int: Array<PoolError>]()
    private var disconnectedDuration = [Int: Int64]()
    
    public init (pool: [PoolConnection], using configuration: PoolConfiguration) {
    
        idle = pool
        
        self.configuration = configuration
        
        for connection in pool {
            
            errorDurations[ObjectIdentifier(connection).hashValue] = 0
            disconnectedDuration[ObjectIdentifier(connection).hashValue] = 0.millisecond
            connectionErrors[ObjectIdentifier(connection).hashValue] = Array<PoolError>()
        }
        
    }
    
    private func createPredicate (connection: PoolConnection) -> (PoolConnection) -> Bool {
        return { $0 === connection }
    }

    public func remove(connection : PoolConnection) -> Bool {
        let closed = connection.close()
        if closed {
            
            let predicate = createPredicate(connection)

            if let index = active.index(where: predicate) {
                active.remove(at: index)
            }
            else if let index = idle.index(where: predicate) {
                idle.remove(at: index)
            }
            else if let index = lent.index(where: predicate) {
                lent.remove(at: index)
            }
            
            errorDurations.removeValue(forKey: ObjectIdentifier(connection).hashValue)
            disconnectedDuration.removeValue(forKey: ObjectIdentifier(connection).hashValue)
            connectionErrors.removeValue(forKey: ObjectIdentifier(connection).hashValue)
            
        }
        return closed
    }

    public func borrow() -> PoolConnection? {
        guard idle.count > 0 else {
            return nil
        }

        guard let connection = idle.first else {
            return nil
        }
        idle.remove(at: 0)
        lent.append(connection)
        return connection
    }

    public func takeBack (connection: PoolConnection) {
        if let index = lent.index(where: createPredicate(connection)) {
            lent.remove(at: index)
            idle.append(connection)
        }
    }
    
    private func nextIdleConnection() throws -> PoolConnection? {
        guard let connection = idle.first else {
            return nil
        }
        idle.remove(at: 0)
        active.append(connection)
        return connection
    }
    
    private func nextSuspectConnection() throws -> PoolConnection? {
        guard let connection = suspect.first else {
            return nil
        }
        suspect.remove(at: 0)
        active.append(connection)
        return connection
    }
    
    private func nextPendingConnection() throws -> PoolConnection? {
        if let connection = pendingRetry.first {
            pendingRetry.remove(at: 0)
            do {
                try connection.open()
            }
            catch {
                if let index = disconnectedDuration.index(forKey: ObjectIdentifier(connection).hashValue) {
                    if now - disconnectedDuration[index].value > configuration.maxReconnectDuration {
                        remove(connection)
                        throw PoolError.maxUnavailableDurationExceeded
                    }
                }
                else {
                    disconnectedDuration.updateValue(now, forKey: ObjectIdentifier(connection).hashValue)
                    pendingRetry.append(connection)
                }
                return nil
            }
            active.append(connection)
            return connection
        }
        return nil
    }
    
    private func nextConnection() throws -> PoolConnection? {
        if idle.count > 0 {
            return try nextIdleConnection()
        }
        else if suspect.count > 0 {
            return try nextSuspectConnection()
        }
        else if pendingRetry.count > 0 {
            return try nextPendingConnection()
        }
        return nil
    }
    
    private func doneWith(connection : PoolConnection) {
        if let index = active.index(where: createPredicate(connection)) {
            active.remove(at: index)
            idle.append(connection)
        }
    }
    
    private func logFailure(connection : PoolConnection) throws {
        // if failed too many times remove from pool
        if let index = errorDurations.index(forKey: ObjectIdentifier(connection).hashValue) {

            let totalErrorDuration = errorDurations[index].value + configuration.retryDelay
            
            errorDurations.updateValue(totalErrorDuration, forKey: ObjectIdentifier(connection).hashValue)
            
            if connection.closed {
                pendingRetry.append(connection)
                disconnectedDuration.updateValue(now, forKey: ObjectIdentifier(connection).hashValue)
            }
            else if totalErrorDuration > configuration.maxErrorDuration {
                suspect.append(connection)
                throw PoolError.maxErrorDurationExeceeded
            }
            
        }
        doneWith(connection)
    }
    
    private func logSuccess(connection : PoolConnection) {
        if let _ = errorDurations.index(forKey: ObjectIdentifier(connection).hashValue) {
            errorDurations.updateValue(0.millisecond, forKey: ObjectIdentifier(connection).hashValue)
        }
    }
    
    public func with(handler: (poolable: PoolConnection) throws -> Any?) throws {
        var hasExecuted = false
        var nappedTime : Duration = 0.millisecond

        while !hasExecuted {
            do {
                guard let connection = try self.nextConnection() else {
                    // We waited longer than permitted for a connections.
                    // Throw a timeout for the user to handle.
                    if configuration.connectionWait < nappedTime {
                        throw PoolError.timeout
                    }
                    nap(configuration.retryDelay)
                    nappedTime += configuration.retryDelay
                    continue
                }
                
                guard !connection.closed else {
                    try self.logFailure(connection)
                    continue
                }
                
                do {
                    try handler(poolable: connection)
                    self.logSuccess(connection)
                    self.doneWith(connection)
                }
                catch {
                    try self.logFailure(connection)
                }
                
                hasExecuted = true
            }
            catch PoolError.timeout {
                throw PoolError.timeout
            }
            catch {}
        }
    }
}
