# WebSockets.jl - Julia 0.7 branch

*Current state 22/7-18*:
It is possible to run the examples with some tweaking.
HttpServer support is working if you 'check out' a rapidly changing set of branches and pull requests on HttpServer and dependencies.

HttpServer support is deprecated and may be fully removed without further warning.

Tests conversion to 0.7 is still rudimentary.


*Current state on 'master' 11/8-18*:

Working on Julia 0.7 and 1.0, but tests still include HttpServer files and will fail.


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
julia> cd(joinpath((WebSockets |> Base.pathof |> splitdir)[1],  "..", "examples"))
julia> readdir()
julia> include("chat_explore.jl")
```
### Open a client side connection
Client side websockets are created by calling `WebSockets.open` (with a server running). Example (you can run this in a second REPL, or in the same):
```julia
julia> include("client_repl_input.jl")
```

### Debugging server side connections

Server side websockets are asyncronous [tasks](https://docs.julialang.org/en/stable/stdlib/parallel/#Tasks-1), which makes debugging harder. The error messages may not spill into the REPL.

##### Using WebSockets.serve
Error messages are directed to a channel. See inline docs: ?Websockets.serve.

##### Using WebSockets.listen
Error messages are by default sent as messages to the client. This is not nice if you're serving pages to the internet.

## What does WebSockets.jl enable?
Some packages rely on WebSockets for communication. You can also use it directly:

- reading and writing between entities you can program or know about
- low latency, high speed messaging
- implement your own 'if X send this, Y do that' subprotocols
- implement registered [websocket subprotocols](https://www.iana.org/assignments/websocket/websocket.xml#version-number)
- heartbeating, relaying
- build a network including browser clients
- convenience functions for gatekeeping with a common interface for HttpServer and HTTP
- writing http handlers and websocket coroutines ('handlers') in the same process can be a security advantage. Modify web page responses to include time-limited tokens in the wsuri.

WebSockets are well suited for user interactions via a browser or [cross-platform applications](https://electronjs.org/). Workload and development time can be moved off Julia resources. Use websockets to pass arguments between compiled functions on both sides; it has both speed and security advantages over passing code for evaluation.

The /logutils folder contains some specialized logging functionality that is quite fast and can make working with multiple asyncronous tasks easier. See /benchmark code for how to use. Logging  may be moved out of WebSockets in the future, depending on how other logging capabilities develop.

You can also have a look at alternative Julia packages: [DandelionWebSockets](https://github.com/dandeliondeathray/DandelionWebSockets.jl) or the implementation currently part of HTTP.jl.

## What are the main downsides to WebSockets (in Julia)?

- Logging. We need customizable and very fast logging for building networked applications.
- Compression is not implemented.
- Possibly non-compliant proxies on the internet, company firewalls.
- 'Warm-up', i.e. compilation when a method is first used. Warm-up is excluded from current benchmarks.
- Garbage collection, which increases message latency at semi-random intervals. See benchmark plots.
- If a connection is closed improperly, the connection task will throw uncaught ECONNRESET and similar messages.
- TCP quirks, including 'warm-up' time with low transmission speed after a pause. Heartbeats can alleviate.
- Neither HTTP.jl or HttpServer.jl are made just for connecting WebSockets. You may need strong points from both.
- Since 'read' is a blocking function, you can easily end up reading indefinitely from both sides.

## Server side example
(Work in progress, see /examples.)
As a first example, we can create a WebSockets echo server. We use named function arguments for more readable stacktraces while debugging.

```julia
using HttpServer
using WebSockets

function coroutine(ws)
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        s == "" && break
        println("Received: ", s)
        if s[1] == "P"
            writeguarded(ws, "No, I'm not!")
        else
            writeguarded(ws, "Why?")
        end
    end
end

function gatekeeper(req, ws)
    println("\nOrigin:", origin(req), "    Target:", target(req), "    subprotocol:", subprotocol(req))
    # Non-browser clients don't send Origin. We liberally accept in this case.
    if origin(req) == "" || origin(req) == "http://127.0.0.1:8080" || origin(req) == "http://localhost:8080"
        coroutine(ws)
    else
        println("Inacceptable request")
    end
end

handle(req, res) = Response(200)

server = Server(HttpHandler(handle),
                WebSocketHandler(gatekeeper))

@async run(server, 8080)
```

Now open a browser on http://127.0.0.1:8080/ and press F12. In the console, type the lines following ≫:
```javascript
≫ws = new WebSocket("ws://127.0.0.1:8080")
 ← WebSocket { url: "ws://127.0.0.1:8080/", readyState: 0, bufferedAmount: 0, onopen: null, onerror: null, onclose: null, extensions: "", protocol: "", onmessage: null, binaryType: "blob" }
≫ws.send("Peer, you're lying!")
 ← undefined
≫ws.onmessage = function(e){console.log(e.data)}
 ← function onmessage()
≫ws.send("Well, then.")
 ← undefined
Why?                                        debugger eval code:1:28
```

If you now navigate or close the browser, this happens:
1. the client side of the websocket connection will quickly send a close request and go away.
2. Server side `readguarded(ws)` has been waiting for messages, but instead closes 'ws' and returns ("", false)
3. `coroutine(ws)` is finished and the task's control flow returns to HttpServer
4. HttpServer does nothing other than exit this task. In fact, it often crashes because
    somebody else (the browser) has closed the underlying TCP stream.
5. The server, which spawned the task, continues to listen for incoming connections, and you're stuck. Ctrl + C!

You could replace 'using HttpServer' with 'using HTTP'. Also:
    Serve -> ServeWS
    HttpHandler -> HTTP.Handler
    WebSocketHandler -> WebSockets.WebsocketHandler


## Client side example

Clients need to use [HTTP.jl](https://github.com/JuliaWeb/HttpServer.jl).


```julia
using HTTP
using WebSockets
function client_one_message(ws)
    printstyled(stdout, "\nws|client input >  ", color=:green)
    msg = readline(stdin)
    if writeguarded(ws, msg)
        msg, stillopen = readguarded(ws)
        println("Received:", String(msg))
        if stillopen
            println("The connection is active, but we leave. WebSockets.jl will close properly.")
        else
            println("Disconnect during reading.")
        end
    else
        println("Disconnect during writing.")
    end
end
function main()
    while true
        println("\nWebSocket client side. WebSocket URI format:")
        println("ws:// host [ \":\" port ] path [ \"?\" query ]")
        println("Example:\nws://127.0.0.1:8080")
        println("Where do you want to connect? Empty line to exit")
        printstyled(stdout, "\nclient_repl_input >  ", color=:green)
        wsuri = readline(stdin)
        wsuri == "" && break
        res = WebSockets.open(client_one_message, wsuri)
        !isa(res, HTTP.Response) && println(res)
    end
    println("Have a nice day")
end

main()
```

See other examples in /test, /benchmark/ and /examples. Some logging utilties for a running relay server are available in /logutils.


## Errors after updating?

The introduction of client side websockets to this package may require changes in your code:
- `using HttpServer` (or import) prior to `using WebSockets` (or import).
- The `WebSocket.id` field is no longer supported. You can generate unique counters by code similar to 'bencmark/functions_open_browsers.jl' COUNTBROWSER.
- You may want to modify you error handling code. Examine WebSocketsClosedError.message.
- You may want to use `readguarded` and `writeguarded` to save on error handling code.?svg=true&branch=master

## Switching from HttpServer to HTTP?
Some types and methods are not exported. See inline docs:
- `Server` -> `WebSockets.ServerWS`
- `WebSocketHandler` -> `WebSockets.WebsocketHandler`
- `run` -> `WebSockets.serve()`
- `Response` -> `HTTP.Response`
- `Request` -> `HTTP.Response`
- `HttpHandler`-> `HTTP.HandlerFunction`

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
