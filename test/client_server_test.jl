# included in runtests.jl
# Tests won't be captured from coroutines, so throw errors
# instead of continuing. The rest of the file should then be skipped.
using Test
include("logformat.jl")
using WebSockets
using Suppressor
# Tell WebSockets we want to accept this subprotocol, as well as no subprotocol
addsubproto("Server start the conversation")
const PORT = 8000
const SURL = "127.0.0.1"
const EXTERNALWSURI = "ws://echo.websocket.org"
const EXTERNALHTTP = "http://httpbin.org/ip"
const MSGLENGTHS = [0 , 125, 126, 127, 2000]
include("client_server_functions.jl")

@info "Test the test method, external server request"
@test 200 == @suppress WebSockets.HTTP.request("GET", EXTERNALHTTP).status

@info "Check server http response, server started with the listen method"
let
    servertask, serverref = startserver(usinglisten = true)
    @test 200 == WebSockets.HTTP.request("GET", "http://$SURL:$PORT").status
    # A warning message is normally output when closing this kind of server
    @suppress closeserver(serverref)
end

@info "Check server http response, ServerWS"
let
    servertask, serverref = startserver()
    @test 200 == WebSockets.HTTP.request("GET", "http://$SURL:$PORT").status
    closeserver(serverref)
end

#@info "Open external server websocket, send messages"
#WebSockets.open(initiatingws, EXTERNALWSURI)



@info "Starting a server.
        Initiate a client side websocket test"
let
    servertask, serverref = startserver(usinglisten = false)
    wsuri = "ws://$SURL:$PORT"
    @debug "We will sleep for 60 s before opening ", wsuri
    sleep(60)
    WebSockets.open(initiatingws, wsuri)
    # A warning message is normally output when closing this kind of server
    @debug "Now the test is finished, we will sleep for 10 s more"
    sleep(10)
    if isready(serverref.out)
    # capture errors, if any were made during the definition.
        @debug take!(serverref.out)
    else
        @debug "No error was trapped by server reference"
    end
    sleep(1)
    @suppress closeserver(serverref)
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
