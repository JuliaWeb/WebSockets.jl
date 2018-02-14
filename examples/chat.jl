using HttpServer
using WebSockets
using JSON

#global Dict to store open connections in
global connections = Dict{String,WebSocket}()
global usernames   = Dict{String,String}()

function decodeMessage( msg )
    JSON.parse(String(copy(msg)))
end

wsh = WebSocketHandler() do req, client
    global connections
    # @show connections[client.id] = client
    while true
        msg = read(client)
        msg = decodeMessage(msg)
        id = msg["id"]
        if haskey(msg,"userName") && !haskey(connections,id)
            uname = msg["userName"]
            println("SETTING USERNAME: $(uname)")
            connections[id] = client
            usernames[id] = uname
        end
        if haskey(msg,"say")
            content = msg["say"]
            println("EMITTING MESSAGE: $(content)")
            for (k,v) in connections
                if k != id
                    write(v, (usernames[id] * ": " * content))
                end
            end
        end
    end
end

httph = HttpHandler() do req::Request, res::Response
    onepage = readstring(Pkg.dir("WebSockets","examples","chat-client.html"))
    Response(onepage)
end

server = Server(httph, wsh)
println("Chat server listening on 8000...")
run(server,8000)
