using HttpServer
using WebSockets

#global Dict to store open connections in
global connections = Dict{Int,WebSocket}()
global usernames   = Dict{Int,String}()

function decodeMessage( msg )
    String(copy(msg))
end
function eval_or_describe_error(strmsg)
   try
       return eval(parse(strmsg, raise = false))
   catch err
        iob = IOBuffer()
        dump(iob, err)
        return String(take!(iob))
   end
end
       
wsh = WebSocketHandler() do req, client
    global connections
    connections[client.id] = client
    while true
        val = client |> read |> decodeMessage |> eval_or_describe_error
        output = String(take!(Base.mystreamvar))
        val = val == nothing ? "<br>" : val
        write(client,"$val<br>$output")
    end
end

onepage = readstring(Pkg.dir("WebSockets","examples","repl-client.html"))
httph = HttpHandler() do req::Request, res::Response
  Response(onepage)
end

server = Server(httph, wsh)
println("Repl server listening on 8080...")

eval(Base,parse("mystreamvar = IOBuffer()"))
eval(Base,parse("STDOUT = mystreamvar"))

run(server,8080)
