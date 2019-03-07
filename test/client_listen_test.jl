# included in runtests.jl
# Very similar to client_serverWS_test.jl
# Test sending / receiving messages correctly,
# closing from within websocket handlers,
# symmetry of client and server side websockets,
# stress tests opening and closing a sequence of servers.
# At this time, we unfortunately get irritating messages
# 'Workqueue inconsistency detected:...'
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

@info "External server http request"
@test 200 == HTTP.request("GET", EXTERNALHTTP).status

@info "Listen: Open, http response, close. Repeat three times. Takes a while."
for i = 1:3
    let
        server = startserver()
        status = HTTP.request("GET", "http://$SURL:$PORT").status
        println("Status($(i)): $(status)")
        @test 200 == status
        close(server)
    end
end

@info "Listen: Client side initates message exchange."
let
    server = startserver()
    WebSockets.open(initiatingws, "ws://$SURL:$PORT")
    close(server)
end

@info "Listen: Server side initates message exchange."
let
    server = startserver()
    WebSockets.open(echows, "ws://$SURL:$PORT", subprotocol = SUBPROTOCOL)
    close(server)
end

@info "Listen: Server side initates message exchange. Close from within server side handler."
let
    server = startserver()
    WebSockets.open(echows, "ws://$SURL:$PORT", subprotocol = SUBPROTOCOL_CLOSE)
    close(server)
end
nothing
