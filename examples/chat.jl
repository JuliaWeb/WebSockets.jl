using HttpServer
using Websockets

#global Dict to store open connections in
global connections = Dict{Int,Websocket}()
global usernames   = Dict{Int,String}()

function decodeMessage( msg )
    bytestring(msg)
end

wsh = WebsocketHandler() do req, client
    global connections
    @show connections[client.id] = client
    while true
        msg = read(client)
        msg = decodeMessage(msg)
        if beginswith(msg, "setusername:")
            println("SETTING USERNAME: $msg")
            usernames[client.id] = msg[13:]
        end
        if beginswith(msg, "say:")
            println("EMITTING MESSAGE: $msg")
            for (k,v) in connections
                if k != client.id
                    write(v, (usernames[client.id] * ": " * msg[5:]))
                end
            end
        end
    end
end

onepage = readall("./examples/chat-client.html")
httph = HttpHandler() do req::Request, res::Response
  Response(onepage)
end

server = Server(httph, wsh)
println("Chat server listening on 8000...")
run(server,8000)
