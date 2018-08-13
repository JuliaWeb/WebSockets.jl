# WebSockets.jl

*Release version*:

[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6) [![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.svg)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)](https://coveralls.io/r/JuliaWeb/WebSockets.jl)


*Development version*:

[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg?branch?master)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6)
[![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.svg?branch=master)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg?branch=master)](https://coveralls.io/r/JuliaWeb/WebSockets.jl?branch=master)
[![Appveyor](https://ci.appveyor.com/api/projects/status/github/JuliaWeb/WebSockets.jl?svg=true&branch=master)](https://ci.appveyor.com/project/JuliaWeb/WebSockets-jl)



Server and client side [Websockets](https://tools.ietf.org/html/rfc6455) protocol in Julia. WebSockets is a small overhead message protocol layered over [TCP](https://tools.ietf.org/html/rfc793). It uses HTTP(S) for establishing the connections.

## Getting started
On Julia pre 0.6, see an earlier version of this repository.
On Julia 0.7 or newer :

```julia
(v0.7) pkg>add WebSockets
julia> using WebSockets
julia> varinfo(WebSockets)
help?> serve
julia> cd(joinpath((WebSockets |> Base.pathof |> splitdir)[1],  "..", "examples"))
julia> readdir()
julia> include("chat_explore.jl")
```
### Open a client side connection
Client side websockets are created by calling `WebSockets.open` (with a server running somewhere). Example (you can run this in a second REPL, or in the same):
```julia
julia> cd(joinpath((WebSockets |> Base.pathof |> splitdir)[1],  "..", "examples"))
julia> include("client_repl_input.jl")
```

### Debugging server side connections

Server side websockets are asyncronous [tasks](https://docs.julialang.org/en/stable/stdlib/parallel/#Tasks-1), which makes debugging harder. The error messages may not spill into the REPL. There are two interfaces to starting a server:

##### Using WebSockets.serve
Error messages are directed to a channel. See inline docs: ?Websockets.serve.

##### Using HTTP.listen
Error messages are by default sent as messages to the client. This is not good practice if you're serving pages to the internet.

## What is nice with WebSockets.jl?
Some packages rely on WebSockets for communication. You can also use it directly:

- reading and writing between entities you can program or know about
- low latency, high speed messaging
- implement your own 'if X send this, Y do that' subprotocols
- implement registered [websocket subprotocols](https://www.iana.org/assignments/websocket/websocket.xml#version-number)
- heartbeating, relaying
- build a network including browser clients
- convenience functions for gatekeeping
- putting http handlers and websocket coroutines ('handlers') in the same process can be a security advantage. It is good practice to modify web page responses to include time-limited tokens in the wsuri.

WebSockets are well suited for user interactions via a browser or [cross-platform applications](https://electronjs.org/) like electron. Workload and development time can be moved off Julia resources, error checking code can be reduced. Use websockets to pass arguments between compiled functions on both sides; it has both speed and security advantages over passing code for evaluation.

The /logutils folder contains some specialized logging functionality that is quite fast and can make working with multiple asyncronous tasks easier. See /benchmark code for how to use. Logging  may be moved entirely out of WebSockets.jl in the future.

You can also have a look at alternative Julia packages: [DandelionWebSockets](https://github.com/dandeliondeathray/DandelionWebSockets.jl) or the implementation currently part of HTTP.jl.

## What are the main downsides to WebSockets (in Julia)?

- Logging. We need customizable and very fast logging for building networked applications.
- Compression is not implemented.
- Possibly non-compliant proxies on the internet, company firewalls.
- 'Warm-up', i.e. compilation when a method is first used. Warm-up is excluded from current benchmarks.
- Garbage collection, which increases message latency at semi-random intervals. See benchmark plots.
- If a connection is closed improperly, the connection task will throw uncaught ECONNRESET and similar messages.
- TCP quirks, including 'warm-up' time with low transmission speed after a pause. Heartbeats can alleviate.
- Since 'read' is a blocking function, you can easily end up reading indefinitely from both sides. See the 'close' function code for an example of non-blocking reads with a timeout.

## Errors after updating?

The introduction of client side websockets to this package in version 0.5.0 may require changes in your code:
- The `WebSocket.id` field is no longer supported. You can generate unique counters by code similar to 'bencmark/functions_open_browsers.jl' COUNTBROWSER.
- You may want to modify you error handling code. Examine WebSocketsClosedError.message.
- You may want to use `readguarded` and `writeguarded` to save on error handling code.
- `Server` -> `WebSockets.ServerWS`
- `WebSocketHandler` -> `WebSockets.WebsocketHandler` (or just pass a function without wrapper)
- `HttpHandler`-> `HTTP.HandlerFunction` (or just pass a function without wrapper)
- `run` -> `serve`
- `Response` -> `HTTP.Response`
- `Request` -> `HTTP.Response`

 You may also want to consider using `target`, `orgin`and `subprotocol`, which
 are compatible with both of the types above.


~~~~
::::::::::::::::
::            ::
::  Made at   ::
::            ::
::::::::::::::::
       ::
 Recurse Center
::::::::::::::::
~~~~
