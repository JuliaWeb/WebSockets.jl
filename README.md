Websockets.jl
=============

This is an implementation of the Websockets protocol in Julia.
It started out as part of webstack.jl, and became it's own repo
when [webstack.jl](https://github.com/hackerschool/webstack.jl) was fragmented
in preparation for making each piece into it's own package.

Websockets.jl is most useful in combination with
[HttpServer.jl](https://github.com/hackerschool/HttpServer.jl),
which takes care of accepting connections and parsing HTTP requests.

Websockets.jl, like the rest of webstack.jl, has only been tested
with the development version of Julia.
You should install [Julia](https://github.com/JuliaLang/julia) from source
if you want to use Websockets.jl.

##Installation/Setup

Websockets.jl and it's dependencies
([HttpServer.jl](https://github.com/hackerschool/HttpServer.jl),
[Httplib.jl](https://github.com/hackerschool/Httplib.jl),
[HttpParser.jl](https://github.com/hackerschool/HttpParser.jl))
will all soon be real Julia packages.
Until then, you'll need to clone them by hand into your `~/.julia` folder.

In your `~/.julia` directory, you need to run:

~~~~
git clone git://github.com/hackerschool/HttpParser.jl.git
git clone git://github.com/hackerschool/Httplib.jl.git
git clone git://github.com/hackerschool/HttpServer.jl.git
git clone git://github.com/hackerschool/Websockets.jl.git
~~~~

You will also need libhttp-parser, so you should follow the directions in
[HttpParser](https://github.com/hackerschool/HttpParser.jl)'s README.

At this point, you can test that it all works
by `cd`ing into the `Websockets.jl` directory and
running `julia examples/chat.jl`.
Open `localhost:8000` in a browser that supports websockets,
and you should see a basic IRC-like chat application.

##Echo server example:

```.jl
using HttpServer
using Websockets

wsh = websocket_handler((req,client) -> begin
    while true
        msg = read(client)
        write(client, msg)
    end
end)
wshh = WebsocketHandler(wsh)
server = Server(wshh)
run(server,8080)
```
