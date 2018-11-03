# included in runtests.jl
# Tests won't be captured from coroutines, so throw errors instead.
# instead of continuing. The rest of the file should then be skipped.
using Test
using WebSockets
import Sockets: IPAddr,
                InetAddr,
                IPv4
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
include("logformat.jl")

@info "External server http request"
@test 200 == WebSockets.HTTP.request("GET", EXTERNALHTTP).status

@info "ServerWS: Open, http response, close. Repeat three times"
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
#=
TODO test wss
        ("wss",         "wss://echo.websocket.org")]
=#
