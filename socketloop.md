---
project: socketloop
tagline: TCP sockets with coroutines
---

## `local socketloop = require'socketloop'`

A socket loop enables coroutine-based asynchronous I/O programming model for
[TCP sockets][TCP socket]. The concept is similar to [Copas], the API and the
implementation are different. Supports both symmetric and asymmetric coroutines.

[Copas]: http://keplerproject.github.com/copas/

----------------------------------------- ----------------------------------------
__basic__
`socketloop([coro]) -> loop`					make a socket loop
`loop.wrap(socket) -> asocket`				wrap a TCP socket to an async socket
`loop.connect(addr,port) -> asocket`		make an async TCP connection
`loop.newthread(handler, ...)`				create a thread for one connection
`loop.newserver(host, port, handler)`		dispatch inbound connections to a function
`loop.start([timeout])`							start the loop
`loop.stop()`										stop the loop (if started)
`loop.dispatch([timeout]) -> true|false`	dispatch pending reads and writes
----------------------------------------- ----------------------------------------

## `socketloop([coro]) -> loop`

Make a new socket loop object. Since we're using select(), it only makes
sense to have one loop per CPU thread / Lua state. The coro arg is the
[coro] module. If given, the created loop dispatches to
[symmetric coroutines][coro] instead of Lua coroutines.

## `loop.wrap(socket) -> asocket`

Wrap a [TCP socket] into an asynchronous socket with the same API
as the original, which btw is kept as `asocket.socket`.

Being asynchronous means that if each socket is used from its own coroutine,
different sockets won't block each other waiting for reads and writes,
as long as the loop is doing the dispatching. The asynchronous methods are:
`connect()`, `accept()`, `receive()`, `send()`, `close()`.

An async socket should only be used inside a loop thread.

## `loop.connect(address, port [,local_address] [,local_port]) -> asocket`

Make a TCP connection and return an async socket.

[TCP socket]: http://w3.impa.br/~diego/software/luasocket/tcp.html

## `loop.newthread(handler, args)`

Create and resume a coroutine (or coro thread, depending on how the loop
was created).

## `loop.newserver(host, port, handler)`

Create a TCP socket and start accepting connections on it, and call
`handler(client_skt)` on a separate coroutine for each accepted connection.

## `loop.start([timeout])`

Start dispatching reads and writes continuously in a loop.
The loop should be started only if there's at least one thread suspended in
an async socket call.

## `loop.stop()`

Stop the dispatch loop (if started).

## `loop.dispatch([timeout]) -> true|false`

Dispatch currently pending reads and writes to their respective coroutines.

