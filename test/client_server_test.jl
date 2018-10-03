# included in runtests.jl
# Tests won't be captured from coroutines, so throw errors
# instead of continuing. The rest of the file should then be skipped.
using Test
include("logformat.jl")
using WebSockets
import Random.randstring
const port_HTTP = 8000
const port_HTTP_ServeWS = 8001
const TCPREF = Ref{WebSockets.TCPServer}()
WebSockets.addsubproto("Server start the conversation")

"""
Takes a websocket. Reads a message, echoes, closes.
"""
function echows(ws::WebSocket)
    @debug "echows ", ws
    data, ok = readguarded(ws)
    if ok
        if writeguarded(ws, data)
            @test true
        else
            @test false
            @error "echows, couldn't write data ", ws
        end
    else
        @test false
        @error "echows, couldn't read ", ws
    end
end

"""
Takes a websocket.
Pings, no check for received pong except for console output.
Sends a message of string lengt. Waits and checks the echo.

"""
function initiatingws(ws::WebSocket, slen::Integer, closebeforeexit::Bool)
    @debug "initiatews ", ws, "\n\t-String length $slen bytes\n"
    send_ping(ws, data = UInt8[1,2,3]) # No check made, this will just output some info message.
    # Since we are sharing the same process as the other side,
    # andhe other side must be reading in order to process the ping-pong.
    yield()
    test_str = randstring(slen)
    forcecopy_str = test_str |> collect |> copy |> join
    if writeguarded(ws, test_str)
        yield()
        readback, ok = readguarded(ws)
        if ok
            # if run by the server side, this test won't be captured.
            @test String(readback) == forcecopy_str
        else
            # if run by the server side, this test won't be captured.
            @test false
            @error "initatews, couldn't read ", ws, " length ", slen
        end
        closebeforeexit && close(ws, statusnumber = 1000)
    else
        @test false
        @error "initatews, couldn't write ", ws, " length ", slen
    end
end

"""
Started as a coroutine for each connection by the server.
"""
function server_gatekeeper(req::WebSockets.Request, ws::WebSocket)
    origin(req) != "" && @error "server_gatekeeper, got origin header as from a browser."
    target(req) != "/" && @error "server_gatekeeper, got origin header as is POST."
    if subprotocol(req) == "Server start the conversation"
        initiatingws(ws, 10, false)
    else
        echows(ws)
    end
    @debug "exiting echows"
end



"""
Server side coroutine started by the listen loop for each accepted connection.
"""
function servercoroutine(s::WebSockets.Stream)
    @debug "servercoroutine", s
    if WebSockets.is_upgrade(s.message)
        @debug "servercoroutine, it's an upgrade"
        WebSockets.upgrade(server_gatekeeper, s)
    end
end


# Start HTTP listen server on port $port_HTTP"
taskHTTP = @async WebSockets.HTTP.listen(servercoroutine,
                                    "127.0.0.1",
                                    port_HTTP,
                                    tcpref = TCPREF,
                                    ratelimits = Dict{IPAddr, WebSockets.RateLimit}(),
                                    tcpisvalid = checkratelimit
                                    )


while !istaskstarted(tas);yield();end

# Start HTTP ServerWS on port $port_HTTP_ServeWS
#server_WS = WebSockets.ServerWS(
#    HTTP.HandlerFunction(req-> HTTP.Response(200)),
#    WebSockets.WebsocketHandler(echows))

#tas = @async WebSockets.serve(server_WS, "127.0.0.1", port_HTTP_ServeWS)
while !istaskstarted(tas);yield();end



function client_initiate((servername, wsuri), stringlength, closebeforeexit)
    # the online websocket test server does not follow our interpretation of
    # protocol for length zero messages.
    stringlength == 0 && occursin("echo.websocket.org", wsuri) && return
    @info("Testing client -> server at $(wsuri), message length $len")
    test_str = randstring(len)
    forcecopy_str = test_str |> collect |> copy |> join
    @debug TCPREF[]
    WebSockets.open(wsuri)
end
=#









#TEMP
const servers = [("HTTP",        "ws://127.0.0.1:$(port_HTTP)")]
s = "HTTP"
wsuri = "ws://127.0.0.1:$(port_HTTP)"
len = 125
closebeforeexit = false





#=const servers = [
        ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"),
        ("HTTTP ServerWS",  "ws://127.0.0.1:$(port_HTTP_ServeWS)"),
        ("ws",          "ws://echo.websocket.org"),
        ("wss",         "wss://echo.websocket.org")]
=#
const stringlengths = [125] #, 125, 126, 127, 2000]
for (servername, wsuri) in servers, len in lengths, closebeforeexit in [false, true]
    closurews(ws) = initiatingws(ws::WebSocket, slen::Integer, closebeforeexit::Bool)

end




# make a very simple http request for the servers with defined http handlers
resp = WebSockets.HTTP.request("GET", "http://127.0.0.1:$(port_HTTP_ServeWS)")
@test resp.status == 200

# Close the servers
close(TCPREF[])
# TEMP
#put!(server_WS.in, HTTP.Servers.KILL)
