using HttpServer
using WebSockets

#global Dict to store open connections in
global connections = Dict{Int,WebSocket}()
global usernames   = Dict{Int,String}()

function decodeMessage( msg )
    bytestring(msg)
end

wsh = WebSocketHandler() do req, client
    global connections
    connections[client.id] = client
    while true
        msg = read(client)
        msg = decodeMessage(msg)
        val = eval(parse(msg))
        output = takebuf_string(Base.mystreamvar)
        val = val == nothing ? "<br>" : val
        write(client,"$val<br>$output")
    end
end

onepage = readall("./examples/repl-client.html")
httph = HttpHandler() do req::Request, res::Response
  Response(onepage)
end

server = Server(httph, wsh)
println("Chat server listening on 8080...")

eval(Base,parse("mystreamvar = IOString()"))
eval(Base,parse("STDOUT = mystreamvar"))

run(server,8080)
