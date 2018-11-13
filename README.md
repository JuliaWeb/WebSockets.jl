# WebSockets.jl

*Release version*:

[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6) [![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.svg)](https://travis-ci.org/JuliaWeb/WebSockets.jl)<!---
Enable coverage when https://github.com/JuliaCI/Coverage.jl/issues/187 is resolved.
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)] (https://coveralls.io/r/JuliaWeb/WebSockets.jl)a --->

Test coverage 96%

*Development version*:

[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg?branch?master)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6)
[![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.svg?branch=master)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
<!---[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg?branch=master)](https://coveralls.io/r/JuliaWeb/WebSockets.jl?branch=master)
[![Appveyor](https://ci.appveyor.com/api/projects/status/github/JuliaWeb/WebSockets.jl?svg=true&branch=master)](https://ci.appveyor.com/project/JuliaWeb/WebSockets-jl)--->

Test coverage 96%


Server and client side [Websockets](https://tools.ietf.org/html/rfc6455) protocol in Julia. WebSockets is a small overhead message protocol layered over [TCP](https://tools.ietf.org/html/rfc793). It uses HTTP(S) for establishing the connections.

## Getting started
Copy this into Julia:

```julia
(v1.0) pkg> add WebSockets
julia> using WebSockets
julia> # define what to do with http requests, and with websocket upgrades.
julia> serverWS =  ServerWS((r) -> WebSockets.Response(200, "OK"),
                            (ws_server) -> (writeguarded(ws_server, "Hello");
                                                readguarded(ws_server)));
julia> # serve on socket 8000, but in a coroutine so we can do other things too.
julia> @async WebSockets.serve(serverWS, 8000)
julia> # We ask for a http response, now as our alter ego the client.
julia> WebSockets.HTTP.get("http://127.0.0.1:8000")
julia> # Talk to ourselves! Print the first response in blue, then hang up.
julia> WebSockets.open("ws://127.0.0.1:8000") do ws_client
           data, success = readguarded(ws_client)
           if success
               printstyled(color=:blue, String(data))
           end
       end
julia> # Tell ourselves, the server in a different coroutine: we can stop listening now.
julia> put!(serverWS.in, "x")
```
More things to do: Access inline documentation and have a look at the examples folder. The testing files demonstrate a variety of uses. Benchmarks show examples of websockets and servers running on separate processes, as oposed to asyncronous tasks.

### About this package
Originally from 2013 and Julia 0.2, the WebSockets API has remained largely unchanged. It now depends on [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl) for establishing the http connections. That package is in ambitious development, and most functionality of this package is already implemented directly in HTTP.jl.

This more downstream package may lag behind the latest version of HTTP.jl, and in so doing perhaps avoid some borderline bugs. This is why the examples and tests do not import HTTP methods directly, but rely on the methods imported in this package. E.g. by using `WebSockets.HTTP.listen` instead of `HTTP.listen` you may possibly be using the previous release of package HTTP. The imported HTTP version is capped so as to avoid possible issues when new versions of HTTP are released.

## What can you do with it?
- read and write between entities you can program or know about
- serve an svg file to the web browser, containing javascript for connecting back through a websocket, adding two-way interaction with graphics
- enjoy very low latency and high speed with a minimum of edge case coding
- implement your own 'if X send this, Y do that' subprotocols. Typically,
  one subprotocol for sensor input, another for graphics or text to a display.
- use registered [websocket subprotocols](https://www.iana.org/assignments/websocket/websocket.xml#version-number) for e.g. remote controlled hardware
- relay user interaction to backend simulations
- build a network including browser clients and long-running relay servers
- use convenience functions for gatekeeping

WebSockets are well suited for user interactions via a browser or [cross-platform applications](https://electronjs.org/) like electron. Workload and development time can be moved off Julia resources, error checking code can be reduced. Preferably use websockets for passing arguments, not code, between compiled functions on both sides; it has both speed and security advantages over passing code for evaluation.

## Other tips
- putting http handlers and websocket coroutines ('handlers') in the same process can be a security advantage. It is good practice to modify web page responses to include time-limited tokens in the address, the wsuri.
- Since `read` and `readguared` are blocking functions, you can easily end up reading indefinitely from any side of the connection. See the `close` function code for an example of non-blocking read with a timeout.
- Compression is not currenlty implemented, but easily adaptable. On local connections, there's probably not much to gain.
- If you worry about milliseconds, TCP quirks like 'warm-up' time with low transmission speed after a pause can be avoided with heartbeats. High-performance examples are missing.
- Garbage collection increases message latency at semi-random intervals, as is visible in  benchmark plots. Benchmarks should include non-memory-allocating examples.

##### Debugging with WebSockets.ServeWS servers
Error messages from run-time are directed to a .out channel. See inline docs: ?Websockets.serve.

##### Debugging with WebSockets.HTTP.listen servers
Error messages may be sent as messages to the client. This may not be good practice if you're serving pages to the internet, but nice while developing locally. There are some inline comments in the source code which may be of help.

## Further development and comments
The issues section is used for planning development: Contributions are welcome.

- The /logutils and /benchmark folders contain some features that are not currently fully implemented (or working?), namely a specialized logger. For application development, we generally require very fast logging and this approach may or may not be sufficiently fast.
- Alternative Julia packages: [DandelionWebSockets](https://github.com/dandeliondeathray/DandelionWebSockets.jl) and the direct implementation in [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl).

## Errors after updating?
### To version 1.1.0
This version is driven by large restructuring in HTTP.jl. We import more functions and types into WebSockets, e.g., WebSockets.Request. The main interface does not, intentionally, change, except for 'origin', which should now be qualified as WebSockets.origin.

### To version 0.5.0
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
