# included in runtests.jl
# Tests won't be captured from coroutines, so throw errors
# instead of continuing. The rest of the file should then be skipped.
using Test
include("logformat.jl")
using WebSockets
import Random.randstring
const PORT = 8000
const SURL = "127.0.0.1"



addsubproto("Server start the conversation")

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
Takes an open websocket, a vector of message lengths and whether or not to close
the websocket (this will be done by the package if not).
Pings, no check for received pong except for console output.
Sends messages of the specified lengths, and checks they are echoed without errors.
"""
function initiatingws(ws::WebSocket, slens::Vector{Int}, closebeforeexit::Bool)
    @debug "initiatews ", ws, "\n\t-String length $slen bytes\n"
    send_ping(ws, data = UInt8[1,2,3]) # No check made, this will just output some info message.
    # Since we are sharing the same process as the other side,
    # andhe other side must be reading in order to process the ping-pong.
    yield()
    for slen in slens
        test_str = randstring(slen)
        forcecopy_str = test_str |> collect |> copy |> join
        if writeguarded(ws, test_str)
            yield()
            readback, ok = readguarded(ws)
            if ok
                # if run by the server side, this test won't be captured.
                if String(readback) == forcecopy_str
                    @test true
                else
                    if ws.server == true
                        @error "initatews, echoed string of length ", slen, " differs from sent "
                    else
                        @test false
                    end
                end
            else
                # if run by the server side, this test won't be captured.
                if ws.server == true
                    @error "initatews, couldn't read ", ws, " length sent is ", slen
                else
                    @test false
                end
            end
            closebeforeexit && close(ws, statusnumber = 1000)
        else
            @test false
            @error "initatews, couldn't write to ", ws, " length ", slen
        end
    end
end



"""
Server side coroutine started by the listen loop for each accepted connection.
"""
function servercoroutine(s::WebSockets.Stream)
    @debug "servercoroutine ", s
    if WebSockets.is_upgrade(s.message)
        @debug "servercoroutine: This is an upgrade"
        WebSockets.upgrade(server_gatekeeper, s)
    else
        @error "servercoroutine, unexpected connection, not an upgrade "
    end
end

closeserver(ref::Ref{WebSockets.TCPServer}) = close(ref[]);yield
closeserver(ref::WebSockets.ServerWS) =  put!(ref.in, "Bugger off!");yield


"""
Returns a task where a server is running, and a reference which can be
used for closing the server or checking trapped errors. The task can be killed
with the same basic effect, and traps errors originating in tasks generated
by core connection functionality.

The reference type depends on argument usinglisten.

The servers can be referred through constants
    server_WS
    TCPREF

To close: one of
    put!(server_WS.in, " ")
    close(TCPREF[])

For 'emergency closedown', just kill the returned task.
"""
function startserver(surl = SURL, port = PORT, usinglisten = false)
    if usinglisten
        reference = Ref{WebSockets.TCPServer}()
        servertask = @async WebSockets.HTTP.listen(servercoroutine,
                                            SURL,
                                            PORT,
                                            tcpref = TCPREF,
                                            tcpisvalid = checkratelimit,
                                            ratelimits = Dict{IPAddr, WebSockets.RateLimit}()
                                            )
        while !istaskstarted(servertask);yield();end
    else
        # Start HTTP ServerWS on port $port_HTTP_ServeWS
        #    const server_WS = WebSockets.ServerWS(
        #        HTTP.HandlerFunction(req-> HTTP.Response(200)),
        #        server_gatekeeper)
        reference =  WebSockets.ServerWS(
                WebSockets.HTTP.Handlers.HandlerFunction(req-> WebSockets.HTTP.Response(200)),
                WebSockets.WebsocketHandler(server_gatekeeper))
        # The below leads to ECONNREFUSED if a request is made.
        #reference =  WebSockets.ServerWS(
        #        req-> HTTP.Response(200),
        #        server_gatekeeper)
        servertask = @async WebSockets.serve(reference, SURL, PORT)
        while !istaskstarted(servertask);yield();end
        if isready(reference.out)
            # capture errors, if any were made during the definition.
            @error take!(myserver_WS.out)
        end
    end
    servertask, reference
end


function client_initiate((servername, wsuri), stringlength, closebeforeexit)
    # the external websocket test server does not follow our interpretation of
    # RFC 6455 the protocol for length zero messages. Skip such tests.
    stringlength == 0 && occursin("echo.websocket.org", wsuri) && return
    @info("Testing client -> server at $(wsuri), message length $len")
    test_str = randstring(len)
    forcecopy_str = test_str |> collect |> copy |> join
    @debug TCPREF[]
    WebSockets.open(wsuri)
end

"""
Started as a coroutine for each connection by the server.
"""
function server_gatekeeper(req::WebSockets.Request, ws::WebSocket)
    origin(req) != "" && @error "server_gatekeeper, got origin header as from a browser."
    target(req) != "/" && @error "server_gatekeeper, got origin header as in a POST request."
    if subprotocol(req) == "Server start the conversation"
        initiatingws(ws, 10, false)
    else
        echows(ws)
    end
    @debug "exiting server_gatekeeper"
end


# Start a WebSockets.ServerWS, check that it responds to an HTTP request, close it
let
    servertask, serverref = startserver()
    @debug "serverref: ", serverref
    @debug "http://$SURL:$PORT"

    @debug "Waiting for 10 seconds "
    sleep(10)
    @debug "Finished waiting"

    # make a very simple http request for the servers with defined http handlers
    resp = WebSockets.HTTP.request("GET", "http://$SURL:$PORT")
    #@test RESP.status == 200
    @debug "That test did not go so well"
    @debug typeof(serverref)
    stack_trace = ""
    if isready(serverref.out)
        stack_trace = take!(myserver_WS.out)
        @debug "Took stack trace"
    else
        @debug "There is no output to be had yet."
    end
    @debug stack_trace



    closeserver(serverref)
    @debug "Closed server"
end





#TEMP
#const servers = [("HTTP",        "ws://127.0.0.1:$(port_HTTP)")]
#s = "HTTP"
#wsuri = "ws://127.0.0.1:$(port_HTTP)"
#len = 125
#closebeforeexit = false





#=const servers = [
        ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"),
        ("HTTTP ServerWS",  "ws://127.0.0.1:$(port_HTTP_ServeWS)"),
        ("ws",          "ws://echo.websocket.org"),
        ("wss",         "wss://echo.websocket.org")]
=#






#=

const stringlengths = [125] #, 125, 126, 127, 2000]

for (servername, wsuri) in servers, closebeforeexit in [false, true]
    closurews(ws) = initiatingws(ws::WebSocket, stringlengths, closebeforeexit::Bool)
end





const TCPREF = Ref{WebSockets.TCPServer}()
const server_WS = WebSockets.ServerWS(
    req-> HTTP.Response(200),
    server_gatekeeper)


# Close the servers
close(TCPREF[])
# TEMP
#put!(server_WS.in, HTTP.Servers.KILL)
# Todo rename
=#
#    const server_WS = WebSockets.ServerWS(
#        HTTP.HandlerFunction(req-> HTTP.Response(200)),
#        server_gatekeeper)
