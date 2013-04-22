Websockets.jl
=============

Websockets in Julia!

##Installation/Setup

These will soon be Julia packages, but until then you'll need to install things by hand.

In your `~/.julia` directory, you need to run:

~~~~
git clone git://github.com/hackerschool/HttpParser.jl.git
git clone git://github.com/hackerschool/Httplib.jl.git
git clone git://github.com/hackerschool/HttpServer.jl.git
git clone git://github.com/hackerschool/Websockets.jl.git
~~~~

You will also need libhttp-parser,
so you should follow the directions in
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
