using HttpServer
using WebSockets
using JSON

struct User
    name::String
    client::WebSocket
end
#global Dict to store open connections in
global connections = Dict{String,User}()

function decodeMessage( msg )
    JSON.parse(String(copy(msg)))
end

wsh = WebSocketHandler() do req, client
    global connections
    while true
        msg = read(client)
        msg = decodeMessage(msg)
        id = msg["id"]
        if haskey(msg,"userName") && !haskey(connections,id)
            uname = msg["userName"]
            println("SETTING USERNAME: $(uname)")
            connections[id] = User(uname,client)
        end
        if haskey(msg,"say")
            content = msg["say"]
            println("EMITTING MESSAGE: $(content)")
            for (k,v) in connections
                if k != id
                    write(v.client, (v.name * ": " * content))
                end
            end
        end
    end
end

httph = HttpHandler() do req::Request, res::Response
    onepage = read(Pkg.dir("WebSockets","examples","chat-client.html"), String)
    Response(onepage)
end

server = Server(httph, wsh)
println("Chat server listening on 8000...")
run(server,8000)
