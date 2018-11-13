# included in runtests.jl

# Test sending / receiving messages correctly,
# closing from within websocket handlers,
# symmetry of client and server side websockets,
# stress tests opening and closing a sequence of servers.
# At this time, we unfortunately get irritating messages
# 'Workqueue inconsistency detected:...'
using Test
using WebSockets
import Sockets: IPAddr,
                InetAddr,
                IPv4
import Random.randstring

include("logformat.jl")
if !@isdefined SUBPROTOCOL
    const SUBPROTOCOL = "Server start the conversation"
    const SUBPROTOCOL_CLOSE = "Server start the conversation and close it from within websocket handler"
end
addsubproto(SUBPROTOCOL)
addsubproto(SUBPROTOCOL_CLOSE)
if !@isdefined(PORT)
    const PORT = 8000
    const SURL = "127.0.0.1"
    const EXTERNALWSURI = "ws://echo.websocket.org"
    const EXTERNALHTTP = "http://httpbin.org/ip"
    const MSGLENGTHS = [0 , 125, 126, 127, 2000]
end
include("client_server_functions.jl")

@info "External server http request"
@test 200 == WebSockets.HTTP.request("GET", EXTERNALHTTP).status

@info "ServerWS: Open, http response, close. Repeat three times. Takes a while."
for i = 1:3
    let
        servertask, serverref = startserver()
        @test 200 == WebSockets.HTTP.request("GET", "http://$SURL:$PORT").status
        closeserver(serverref)
    end
end

@info "ServerWS: Client side initates message exchange."
let
    servertask, serverref = startserver()
    WebSockets.open(initiatingws, "ws://$SURL:$PORT")
    closeserver(serverref)
end

@info "ServerWS: Server side initates message exchange."
let
    servertask, serverref = startserver()
    WebSockets.open(echows, "ws://$SURL:$PORT", subprotocol = SUBPROTOCOL)
    closeserver(serverref)
end

@info "ServerWS: Server side initates message exchange. Close from within server side handler."
let
    servertask, serverref = startserver()
    WebSockets.open(echows, "ws://$SURL:$PORT", subprotocol = SUBPROTOCOL_CLOSE)
    closeserver(serverref)
end
nothing
