WebSockets.jl
=============

[![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.png)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)](https://coveralls.io/r/JuliaWeb/WebSockets.jl)
[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6)


# (still temporary version)
[Websockets](https://tools.ietf.org/html/rfc6455) is a message protocol on top of TCP with less overhead and restrictions than HTTP(S). Originally, scripts hosted on a web page initiated the connection via HTTP/S. This implementation can now act as either client (`open`) or server (`listen` or `serve`).


Client websockets are created by calling `open`. Just import [HTTP.jl](https://github.com/JuliaWeb/HttpServer.jl) before
WebSockets.

Server websockets are always asyncronous [tasks](https://docs.julialang.org/en/stable/stdlib/parallel/#Tasks-1), spawned by 
[HttpServer.jl](https://github.com/JuliaWeb/HttpServer.jl) or HTTP.jl.


## What does `WebSockets.jl` enable?
- read
- write
- build a network
- heartbeating
- define your own protocols, or implement existing ones
- low latency and overhead

Some other [protocols](https://github.com/JuliaInterop) struggle including browsers and Javascript in the network, although for example ZMQ / IJulia / Jupyter says otherwise. WebSockets are well suited for user interactions via a browser. When respecting Javascript as a compiled language with powerful parallel capabilities, user interaction and graphics workload, even development can be moved off Julia resources.

You may also prefer Julia packages [DandelionWebSockets](https://github.com/dandeliondeathray/DandelionWebSockets.jl) or the implementation directly in HTTP.jl itself.

## What are the main downsides to WebSockets (in Julia)?

- Logging. We need customizable and very fast logging for building networked applications.
- Security. Http(s) servers are currently not working. Take care.
- Non-compliant proxies on the internet, company firewalls. Commercial applications often use competing technologies for this reason. HTTP.jl lets you access the network without the restriction of structured messages.
- 'Warm-up', i.e. compilation when a method is first used. These are excluded from current benchmarks.
- Garbage collection, which increases message latency at semi-random intervals. See benchmark plots.
- TCP. If a connection is broken, the underlying protocol will throw ECONNRESET messages.
- TCP quirks, including 'warm-up' time with low transmission speed after a pause. Heartbeats can alleviate.
- Neither HTTP.jl or HttpServer.jl are made just for connecting WebSockets. You may need strong points from both. 
- The optional dependencies increases load time compared to fixed dependencies.


## Server side

As a first example, we can create a WebSockets echo server:

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


## Client side

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

The output in a console session is barely readable, which is irritating. To build real-time applications, we need more code.

Some logging utilties for a running relay server are available in /logutils.



## Installation/Setup

WebSockets.jl must be used with either HttpServer.jl or HTTP.jl, but neither is a dependency of this package. You will need to first add one or both, i.e.:

~~~julia
julia> Pkg.add("HttpServer")
julia> Pkg.add("HTTP")
julia> Pkg.add("WebSockets")
~~~



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
