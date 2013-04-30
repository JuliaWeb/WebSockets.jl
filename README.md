WebSockets.jl
=============

This is an implementation of the WebSockets protocol in Julia.
It started out as part of webstack.jl, and became it's own repo
when [webstack.jl](https://github.com/hackerschool/webstack.jl) was fragmented
in preparation for making each piece into it's own package.

WebSockets.jl is most useful in combination with
[HttpServer.jl](https://github.com/hackerschool/HttpServer.jl),
which takes care of accepting connections and parsing HTTP requests.

WebSockets.jl, like the rest of webstack.jl, has only been tested
with the development version of Julia.
You should install [Julia](https://github.com/JuliaLang/julia) from source
if you want to use WebSockets.jl.

##Installation/Setup

WebSockets.jl and it's dependencies
([HttpServer.jl](https://github.com/hackerschool/HttpServer.jl),
[HttpCommon.jl](https://github.com/hackerschool/HttpCommon.jl),
[HttpParser.jl](https://github.com/hackerschool/HttpParser.jl))
are all Julia packages.
This means that all you have to do is run `Pkg.add("WebSockets")`
and everything will be installed.

You will also need libhttp-parser, so you should follow the directions in
[HttpParser](https://github.com/hackerschool/HttpParser.jl)'s README.

At this point, you can test that it all works
by `cd`ing into the `~/.julia/WebSockets.jl` directory and
running `julia examples/chat.jl`.
Open `localhost:8000` in a browser that supports WebSockets,
and you should see a basic IRC-like chat application.

##Echo server example:

```.jl
using HttpServer
using WebSockets

wsh = websocket_handler((req,client) -> begin
    while true
        msg = read(client)
        write(client, msg)
    end
end)
wshh = WebSocketHandler(wsh)
server = Server(wshh)
run(server,8080)
```
