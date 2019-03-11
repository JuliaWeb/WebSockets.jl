# included in runtests.jl
# Very similar to client_serverWS_test.jl
# Test sending / receiving messages correctly,
# closing from within websocket handlers,
# symmetry of client and server side websockets,
# stress tests opening and closing a sequence of servers.
# At this time, we unfortunately get irritating messages
# 'Workqueue inconsistency detected:...'

# @info "External server http request"
# @test 200 == HTTP.request("GET", EXTERNALHTTP).status

@info "Listen: Open, http response, close. Repeat three times. Takes a while."
for i = 1:3
    let
        server = startserver(url=SURL,port=PORT)
        status = HTTP.request("GET", "http://$SURL:$PORT").status
        println("Status($(i)): $(status)")
        @test 200 == status
        close(server)
    end
end

@info "Listen: Client side initates message exchange."
let
    server = startserver(url=SURL,port=PORT)
    WebSockets.open(initiatingws, "ws://$SURL:$PORT")
    close(server)
end

@info "Listen: Server side initates message exchange."
let
    server = startserver(url=SURL,port=PORT)
    WebSockets.open(echows, "ws://$SURL:$PORT", subprotocol = SUBPROTOCOL)
    close(server)
end

@info "Listen: Server side initates message exchange. Close from within server side handler."
let
    server = startserver(url=SURL,port=PORT)
    WebSockets.open(echows, "ws://$SURL:$PORT", subprotocol = SUBPROTOCOL_CLOSE)
    close(server)
end
nothing
