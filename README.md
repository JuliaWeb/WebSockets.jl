WebSockets.jl
=============
[![Build Status](https://travis-ci.org/hackerschool/WebSockets.jl.png)](https://travis-ci.org/hackerschool/WebSockets.jl)

This is a server-side implementation of the WebSockets protocol in Julia.
If you want to write a web app in Julia that uses websockets, you'll need this package.

WebSockets.jl is most useful in combination with
[HttpServer.jl](https://github.com/hackerschool/HttpServer.jl),
which takes care of accepting connections and parsing HTTP requests.
As you can see in the example code at the bottom of the README,
you just define a function that takes a request and a client.
The request is an HTTP Request from [HttpCommon.jl](https://github.com/hackerschool/HttpCommon.jl);
the client is a `WebSocket`, from this package.
Your server can `write` data to the WebSocket,
`read` data from it, send `ping` or `pong` messages, or `close` the connection.

On a historical note, this pacakage started out as part of webstack.jl, and became it's own repo
when [webstack.jl](https://github.com/hackerschool/webstack.jl) was fragmented
in preparation for making each piece into it's own package.

WebSockets.jl, like the rest of webstack.jl, has only been tested
with the development version of Julia.
You should install [Julia](https://github.com/JuliaLang/julia) from source
if you want to use WebSockets.jl.

##Installation/Setup

```jl
# in REQUIRE
WebSockets 0.0.1

# in REPL
julia> Pkg2.add("WebSockets")
```

This will install WebSockets.jl and it's dependencies
([HttpServer.jl](https://github.com/hackerschool/HttpServer.jl),
[HttpCommon.jl](https://github.com/hackerschool/HttpCommon.jl),
[HttpParser.jl](https://github.com/hackerschool/HttpParser.jl)).

At this point, you can test that it all works
by `cd`ing into the `~/.julia/WebSockets.jl` directory and
running `julia examples/chat.jl`.
Open `localhost:8000` in a browser that supports WebSockets,
and you should see a basic IRC-like chat application.

##Echo server example:

~~~~.jl
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
~~~~

To play with a WebSockets echo server, you can:

1. Paste the above code in to the Julia REPL
2. Open `localhost:8080` in Chrome
3. Open the Chrome developers tools console
4. Type `ws = new WebSocket("ws://localhost:8080");` into the console
5. Type `ws.send("hi")` into the console.
6. Switch to the 'Network' tab; click on the request; click on the 'frames' tab.
7. You will see the two frames containing "hi": one sent and one received.

~~~~
:::::::::::::
::         ::
:: Made at ::
::         ::
:::::::::::::
     ::
Hacker School
:::::::::::::
~~~~
