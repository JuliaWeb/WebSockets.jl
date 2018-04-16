WebSockets.jl
=============

[![Build Status](https://travis-ci.org/JuliaWeb/WebSockets.jl.png)](https://travis-ci.org/JuliaWeb/WebSockets.jl)
[![Coverage Status](https://img.shields.io/coveralls/JuliaWeb/WebSockets.jl.svg)](https://coveralls.io/r/JuliaWeb/WebSockets.jl)

[![WebSockets](http://pkg.julialang.org/badges/WebSockets_0.6.svg)](http://pkg.julialang.org/?pkg=WebSockets&ver=0.6)

Temporary badges:
[![Build status](https://ci.appveyor.com/api/projects/status/sx6i51rjc9ajjdh8?svg=true)](https://ci.appveyor.com/project/hustf/websockets-jl-nfuiv)

[![Build status](https://ci.appveyor.com/api/projects/status/sx6i51rjc9ajjdh8/branch/master?svg=true)](https://ci.appveyor.com/project/hustf/websockets-jl-nfuiv/branch/master)

[![Build status](https://ci.appveyor.com/api/projects/status/sx6i51rjc9ajjdh8/branch/master?svg=true)](https://ci.appveyor.com/project/hustf/websockets-jl-nfuiv/branch/change_dependencies)

This is an implementation of the WebSockets protocol in Julia for both server-side and client-side applications.

This package works with either [HttpServer.jl](https://github.com/JuliaWeb/HttpServer.jl) or [HTTP.jl](https://github.com/JuliaWeb/HttpServer.jl), which is what you use to set up a server that accepts HTTP(S) connections.

## Temporary picture
This test picture shows the package neighborhood prior to this change.
Some of the dependencies are test-only dependencies.
![Dependencies and test dependencies neighborhood](examples/serve_verbose/svg/ws_neighborhood.svg)

## Using with HttpServer.jl

As a first example, we can create a WebSockets echo server:

```julia
using HttpServer
using WebSockets

wsh = WebSocketHandler() do req,client
    while true
        msg = read(client)
        println(msg) # Write the received message to the REPL
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

## Using with HTTP.jl

The following example demonstrates how to use WebSockets.jl as bother a server and client.

```julia

using HTTP
using WebSockets
using Base.Test

port = 8000

# Start the echo server
@async HTTP.listen("127.0.0.1",UInt16(port)) do http
    if WebSockets.is_upgrade(http.message)
        WebSockets.upgrade(http) do ws
            while ws.state == WebSockets.CONNECTED
                msg = String(read(ws))
                println(msg) # Write the received message to the REPL
                write(ws,msg)
            end
        end
    end
end

sleep(2)

# Connect a client to the server above
WebSockets.open("ws://127.0.0.1:$(port)") do ws
    write(ws, "Foo")
    @test String(read(ws)) == "Foo"

    write(ws, "Bar")
    @test String(read(ws)) == "Bar"

    close(ws)
end
```

## What can you do with a `WebSocket`?
You can:

* `write` data to it
* `read` data from it
* send `ping` or `pong` messages
* `close` the connection

## Installation/Setup

WebSockets.jl must be used with either HttpServer.jl or HTTP.jl, but neither is a dependency of this package, so you will need to first add one of the two, i.e.

~~~julia
julia> Pkg.add("HttpServer")
~~~

or

~~~julia
julia> Pkg.add("HTTP")
~~~

Once you have one of the two, you can add WebSockets.jl via

~~~julia
julia> Pkg.add("WebSockets")
~~~

At this point, you can use the examples below to test that it all works.

## [Chat client/server example](https://github.com/JuliaWeb/WebSockets.jl/blob/master/examples/chat.jl):

1. From the REPL, run

```julia
include(joinpath(Pkg.dir("WebSockets"),"examples","chat.jl"));
```

2. In a web browser, open `localhost:8000`
3. You should see a basic IRC-like chat application


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
5. Type `ws.send("hi")` into the console and you should see "hi" printed to the REPL
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
