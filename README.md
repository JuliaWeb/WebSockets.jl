WebSockets.jl
=============

[![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.png)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)](https://coveralls.io/r/JuliaWeb/WebSockets.jl)

[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.3.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.3)
[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.4.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.4)

This is a server-side implementation of the WebSockets protocol in Julia. If you want to write a web app in Julia that uses WebSockets, you'll need this package.

This package works with [HttpServer.jl](https://github.com/JuliaWeb/HttpServer.jl), which is what you use to set up a server that accepts HTTP(S) connections.

As a first example, we can create a WebSockets echo server:

```julia
using HttpServer
using WebSockets

wsh = WebSocketHandler() do req,client
    while true
        msg = read(client)
        write(client, msg)
    end
  end

server = Server(wsh)
run(server,8080)
```

This sets up a server running on localhost, port 8080.
It will accept WebSockets connections.
The function in `wsh` will be called once per connection; it takes over that connection.
In this case, it reads each `msg` from the `client` and then writes the same message back: a basic echo server.

The function that you pass to the `WebSocketHandler` constructor takes two arguments:
a `Request` from [HttpCommon.jl](https://github.com/JuliaWeb/HttpCommon.jl/blob/master/src/HttpCommon.jl#L142),
and a `WebSocket` from [here](https://github.com/JuliaWeb/WebSockets.jl/blob/master/src/WebSockets.jl#L17).

## What can you do with a `WebSocket`?
You can:

* `write` data to it
* `read` data from it
* send `ping` or `pong` messages
* `close` the connection

## Installation/Setup

~~~julia
julia> Pkg.add("WebSockets")
~~~

At this point, you can use the examples below to test that it all works.

## [Chat client/server example](https://github.com/JuliaWeb/WebSockets.jl/blob/master/examples/chat.jl):

1. Move to the `~/.julia/<version>/WebSockets` directory
2. Run `julia examples/chat.jl`
3. In a web browser, open `localhost:8000`
4. You should see a basic IRC-like chat application


## Echo server example:

~~~julia
using HttpServer
using WebSockets

wsh = WebSocketHandler() do req,client
    while true
        msg = read(client)
        write(client, msg)
    end
  end

server = Server(wsh)
run(server,8080)
~~~

To play with a WebSockets echo server, you can:

1. Paste the above code in to the Julia REPL
2. Open `localhost:8080` in Chrome
3. Open the Chrome developers tools console
4. Type `ws = new WebSocket("ws://localhost:8080");` into the console
5. Type `ws.send("hi")` into the console.
6. Switch to the 'Network' tab; click on the request; click on the 'frames' tab.
7. You will see the two frames containing "hi": one sent and one received.

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
