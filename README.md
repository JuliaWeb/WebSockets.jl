# WebSockets.jl


[![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.png)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)](https://coveralls.io/r/JuliaWeb/WebSockets.jl)
[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6)


Server and client side [Websockets](https://tools.ietf.org/html/rfc6455) protocol in Julia. WebSockets is a small overhead message protocol layered over [TCP](https://tools.ietf.org/html/rfc793). It uses HTTP(S) for establishing the connections. 

## Getting started
WebSockets.jl must be used with either HttpServer.jl or HTTP.jl, but neither is a dependency of this package. You will need to first add one or both, i.e.:

```julia
julia> Pkg.add("HttpServer") 
julia> Pkg.add("HTTP")
julia> Pkg.add("WebSockets")
```
### Open a client side connection
Client side websockets are created by calling `WebSockets.open` (with a server running). Client side websockets require [HTTP.jl](https://github.com/JuliaWeb/HttpServer.jl). 

### Accept server side connections

Server side websockets are asyncronous [tasks](https://docs.julialang.org/en/stable/stdlib/parallel/#Tasks-1), spawned by either
[HttpServer.jl](https://github.com/JuliaWeb/HttpServer.jl) or HTTP.jl. 

##### Using HttpServer
Call `run`, which is a wrapper for calling `listen`. See inline docs.

##### Using HTTP
Call `WebSockets.serve`, which is a wrapper for `HTTP.listen`. See inline docs.

## What does WebSockets.jl enable?

- reading and writing between entities you can program or know about
- low latency messaging
- implement your own 'if X send this, Y do that' subprotocols
- implement registered [websocket subprotocols](https://www.iana.org/assignments/websocket/websocket.xml#version-number)
- heartbeating, relaying
- build a network including browser clients
- convenience functions for gatekeeping with a common interface for HttpServer and HTTP
- writing http handlers and websocket coroutines ('handlers') in the same process can be an advantage. Exchanging unique tokens via http(s)
  before accepting websockets is recommended for improved security

WebSockets are well suited for user interactions via a browser or [cross-platform applications](https://electronjs.org/). User interaction and graphics workload, even development time can be moved off Julia resources. Use websockets to pass arguments between compiled functions on both sides; don't evaluate received code!

The /logutils folder contains some specialized logging functionality that is quite fast and can make working with multiple asyncronous tasks easier. See /benchmark code for how to use. Logging  may be moved out of WebSockets in the future, depending on how other logging capabilities develop.

You should also have a look at alternative Julia packages: [DandelionWebSockets](https://github.com/dandeliondeathray/DandelionWebSockets.jl) or the implementation currently part of HTTP.jl.

## What are the main downsides to WebSockets (in Julia)?

- Logging. We need customizable and very fast logging for building networked applications.
- Security. Julia's Http(s) servers are currently not fully working to our knowledge.
- Compression is not implemented.
- Possibly non-compliant proxies on the internet, company firewalls. 
- 'Warm-up', i.e. compilation when a method is first used. Warm-up is excluded from current benchmarks.
- Garbage collection, which increases message latency at semi-random intervals. See benchmark plots.
- If a connection is closed improperly, the connection task will throw uncaught ECONNRESET and similar messages.
- TCP quirks, including 'warm-up' time with low transmission speed after a pause. Heartbeats can alleviate.
- Neither HTTP.jl or HttpServer.jl are made just for connecting WebSockets. You may need strong points from both.
- The optional dependencies may increase load time compared to fixed dependencies.
- Since 'read' is a blocking function, you can easily end up reading indefinitely from both sides.

## Server side example

As a first example, we can create a WebSockets echo server. We use named function arguments for more readable stacktraces while debugging.

```julia
using HttpServer
using WebSockets

function coroutine(ws)
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        if s == ""
            break
        end
        println(s)
        if s[1] == "P"
            writeguarded(ws, "No, I'm not!")
        else
            writeguarded(ws, "Why?")
        end
    end
end

function gatekeeper(req, ws)
    if origin(req) == "http://127.0.0.1:8080" || origin(req) == "http://localhost:8080"
        coroutine(ws)
    else
        println(origin(req))
    end
end

handle(req, res) = Response(200)

server = Server(HttpHandler(handle), 
                WebSocketHandler(gatekeeper))

run(server, 8080)
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
    somebody else (the browser) has closed the underlying TCP stream. If you had replaced the last Julia line with '@async run(server, 8080', you would see some long error messages.
5. The server, which spawned the task, continues to listen for incoming connections, and you're stuck. Ctrl + C!

You could replace 'using HttpServer' with 'using HTTP'. Also:
    Serve -> ServeWS
    HttpHandler -> HTTP.Handler
    WebSocketHandler -> WebSockets.WebsocketHandler


## Client side example

You need to use [HTTP.jl](https://github.com/JuliaWeb/HttpServer.jl). 

What you can't do is use a browser as the server side. The server side can be the example above, running in an asyncronous task. The server can also be running in a separate REPL, or in a a parallel task. The benchmarks puts the `client` side on a parallel task. 

The following example 
- runs server in an asyncronous task, client in the REPL control flow
- uses [Do-Block-Syntax](https://docs.julialang.org/en/v0.6.3/manual/functions/#Do-Block-Syntax-for-Function-Arguments-1), which is a style choice
- the server `ugrade` skips checking origin(req)`
- the server is invoked with `listen(..)` instead of `serve()`
- read(ws) and write(ws, msg) instead of readguarded(ws), writeguarded(ws) 

```julia

using HTTP
using WebSockets

const PORT = 8080

# Server side
@async HTTP.listen("127.0.0.1", PORT) do http
    if WebSockets.is_upgrade(http.message)
        WebSockets.upgrade(http) do req, ws
            while isopen(ws)
                msg = String(read(ws))
                write(ws, msg)
            end
        end
    end
end

sleep(2)


WebSockets.open("ws://127.0.0.1:$PORT") do ws
    write(ws, "Peer, about your hunting")
    println("echo received:" * String(read(ws)))
end
```

The output from the example in a console session is barely readable. Output from asyncronous tasks are intermixed. To build real-time applications, we need more code. See other examples in /test, /benchmark/ and /examples.

Some logging utilties for a running relay server are available in /logutils.

## Errors after updating?

The introduction of client side websockets to this package may require changes in your code:
- `using HttpServer` (or import) prior to `using WebSockets` (or import).
- The `WebSocket.id` field is no longer supported. You can generate unique counters by code similar to 'bencmark/functions_open_browsers.jl' COUNTBROWSER.
- You may want to modify error handling code. Examine WebSocketsClosedError.message.
- You may want to use `readguarded` and `writeguarded` to save on error handling code.

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
