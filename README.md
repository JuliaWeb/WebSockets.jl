Websockets.jl
=============

Websockets in Julia!

Echo server example:

```.jl
using Http
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