ConnectionPool
==========
[![Swift][swift-badge]][swift-url]
[![Platform][platform-badge]][platform-url]
[![License][mit-badge]][mit-url]
[![Slack][slack-badge]][slack-url]

Library for managing a pool of connection.

## Features

- [x] Round Robin
- [x] Failed Connection Retry

## Example

```swift
final class PooledSockets: PoolConfiguration {

    // Set how long a pool can suffer a continued series of errors before it is removed from the pool.
    var maxErrorDuration: Duration = 1.minute
    
    // Set how long to wait before trying to issue a connection to a consumer after finding none available.
    var retryDelay: Duration = 10.milliseconds
    
    // How long to wait for a connection to be available before giving up.
    var connectionWait: Duration = 30.milliseconds
    
    // How long to keep trying to reconnect a closed socket before removing it from the pool.
    var maxReconnectDuration: Duration = 5.minutes

    init(connections : [TCPConnection]) throws {
        let pool = ConnectionPool<TCPConnection>(pool: connections, using: self)
        
        // Get a connection from the pool to use.
        try pool.with { connection in
            // Use the connection as needed.
            connection.send(Data("Hello Zewo"))
        }
        
        // Borrow a connection from the pool.
        // While borrowed the connection will not be used by the pool.
        // The pool will begin to use connection when it is returned.
        if let borrowedConnection = pool.borrow() {
            // Return a borrowed connection to the pool.
            pool.takeBack(borrowedConnection)
        }
        
        if let borrowedConnection = pool.borrow() {
            // Remove a connection from the pool.
            pool.remove(borrowedConnection)
        }
    }
}

```

## Community

[![Slack](http://s13.postimg.org/ybwy92ktf/Slack.png)](https://zewo-slackin.herokuapp.com)

Join us on [Slack](https://zewo-slackin.herokuapp.com).

License
-------

**ConnectionPool** is released under the MIT license. See LICENSE for details.

[swift-badge]: https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat
[swift-url]: https://swift.org
[platform-badge]: https://img.shields.io/badge/Platform-Mac%20%26%20Linux-lightgray.svg?style=flat
[platform-url]: https://swift.org
[mit-badge]: https://img.shields.io/badge/License-MIT-blue.svg?style=flat
[mit-url]: https://tldrlegal.com/license/mit-license
[slack-image]: http://s13.postimg.org/ybwy92ktf/Slack.png
[slack-badge]: https://zewo-slackin.herokuapp.com/badge.svg
[slack-url]: http://slack.zewo.io
