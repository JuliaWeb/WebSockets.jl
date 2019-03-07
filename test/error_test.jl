# included in runtests.jl
const FURL = "ws://127.0.0.1"
const FPORT = 8092

@info "Start a server with a ws handler that is unresponsive. \nClose from client side. The " *
      " close handshake aborts after $(WebSockets.TIMEOUT_CLOSEHANDSHAKE) seconds..."
wsserver = WebSockets.WSServer(
    HTTP.RequestHandlerFunction(req-> HTTP.Response(200)),
    HTTP.StreamHandlerFunction(stream -> (sleep(16);return)))

startserver(wsserver, surl=FURL, port=FPORT)
res = WebSockets.open((_) -> nothing, FURL*FPORT);
@test res.status == 101

@info "Start a server with a ws handler that always reads guarded."
sleep(1)
wsserver = WebSockets.WSServer(   HTTP.RequestHandlerFunction(req -> HResponse(200)),
                        WebSockets.WebsocketHandler() do req, ws_serv
                                                while isopen(ws_serv)
                                                    readguarded(ws_serv)
                                                end
                                            end);
tas = @async serve(wsserver, "127.0.0.1", FPORT)
while !istaskstarted(tas); yield(); end
sleep(1)

@info "Attempt to read guarded from a closing ws|client. Check for return false."
sleep(1)
WebSockets.open(FURL) do ws_client
        close(ws_client)
        @test (UInt8[], false) == readguarded(ws_client)
    end;
sleep(1)


@info "Attempt to write guarded from a closing ws|client. Check for return false."
sleep(1)
WebSockets.open(FURL) do ws_client
    close(ws_client)
    @test false == writeguarded(ws_client, "writethis")
end;
sleep(1)


@info "Attempt to read from closing ws|client. Check caught error."
sleep(1)
try
    WebSockets.open(FURL) do ws_client
        close(ws_client)
        read(ws_client)
    end
catch err
    @test typeof(err) <: ErrorException
    @test err.msg == "Attempt to read from closed WebSocket|client. First isopen(ws), or use readguarded(ws)!"
end
sleep(1)


@info "Attempt to write to a closing ws|client (this takes some time, there is no check
      in WebSockets against it). Check caught error."
sleep(1)
try
    WebSockets.open(FURL) do ws_client
        close(ws_client)
        write(ws_client, "writethis")
    end
catch err
    show(err)
     @test typeof(err) <: WebSocketClosedError
     @test err.message == " while open ws|client: stream is closed or unusable"
end

put!(wsserver.in, "x")


@info "Start a server. The wshandler use global channels for inspecting caught errors."
sleep(1)
chfromserv=Channel(2)
wsserver = WebSockets.WSServer(   HTTP.RequestHandlerFunction(req-> HTTP.Response(200)),
                        WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                    try
                                                        read(ws_serv)
                                                    catch err
                                                        put!(chfromserv, err)
                                                        put!(chfromserv, stacktrace(catch_backtrace())[1:2])
                                                    end
                                                end
                                            end);
tas = @async serve(wsserver, "127.0.0.1", FPORT)
while !istaskstarted(tas); yield(); end
sleep(3)

@info "Open a ws|client, close it out of protocol. Check server error on channel."
global res = WebSockets.open((ws)-> close(ws.socket), FURL)
@test res.status == 101
sleep(1)
global err = take!(chfromserv)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
global stack_trace = take!(chfromserv)
if VERSION <= v"1.0.2"
    # Stack trace on master is zero. Unknown cause.
    @test length(stack_trace) == 2
end
put!(wsserver.in, "x")
sleep(1)

@info "Start a server. Errors are output on built-in channel"
sleep(1)
global wsserver = WebSockets.WSServer(   HTTP.RequestHandlerFunction(req-> HTTP.Response(200)),
                               WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                        read(ws_serv)
                                                end
                                            end);
global tas = @async serve(wsserver, "127.0.0.1", FPORT, false)
while !istaskstarted(tas); yield(); end
sleep(3)

@info "Open a ws|client, close it out of protocol. Check server error on server.out channel."
sleep(1)
WebSockets.open((ws)-> close(ws.socket), FURL);
global err = take!(wsserver.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
sleep(1)
global stack_trace = take!(wsserver.out);
if VERSION <= v"1.0.2"
    # Stack trace on master is zero. Unknown cause.
    @test length(stack_trace) in [5, 6]
end

while isready(wsserver.out)
    take!(wsserver.out)
end
sleep(1)


@info "Open ws|clients, close using every status code from RFC 6455 7.4.1\n" *
      "  Verify error messages on server.out reflect the codes."
sleep(1)
for (ke, va) in WebSockets.codeDesc
    @info "Closing ws|client with reason ", ke, " ", va
    sleep(0.3)
    WebSockets.open((ws)-> close(ws, statusnumber = ke), FURL)
    wait(wsserver.out)
    global err = take!(wsserver.out)
    @test typeof(err) <: WebSocketClosedError
    @test err.message == "ws|server respond to OPCODE_CLOSE $ke:$va"
    wait(wsserver.out)
    stacktra = take!(wsserver.out)
    if VERSION <= v"1.0.2"
        # Unknown cause, nighly behaves differently
        @test length(stacktra) == 0
    end
    while isready(wsserver.out)
        take!(wsserver.out)
    end
    sleep(1)
end

@info "Open a ws|client, close it using a status code from RFC 6455 7.4.1\n" *
      " and also a custom reason string. Verify error messages on server.out reflect the codes."

sleep(1)
global va = 1000
@info "Closing ws|client with reason", va, " ", WebSockets.codeDesc[va], " and goodbye!"
WebSockets.open((ws)-> close(ws, statusnumber = va, freereason = "goodbye!"), FURL)
wait(wsserver.out)
global err = take!(wsserver.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1000:goodbye!"
global stack_trace = take!(wsserver.out)
sleep(1)


@info "Open a ws|client. Throw an InterruptException to it. Check that the ws|server\n " *
    "error shows the reason for the close."
sleep(1)
function selfinterruptinghandler(ws)
    task = @async WebSockets.open((ws)-> read(ws), FURL)
    sleep(3)
    @async Base.throwto(task, InterruptException())
    sleep(1)
    nothing
end
WebSockets.open(selfinterruptinghandler, FURL)
sleep(6)
global err = take!(wsserver.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1006: while read(ws|client received InterruptException."
global stack_trace = take!(wsserver.out)
put!(wsserver.in, "close server")
sleep(2)
