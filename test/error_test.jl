# included in runtests.jl
using Test
using Base64
using WebSockets
import WebSockets:  HandlerFunction,
                    WebsocketHandler,
                    Response
include("logformat.jl")
const THISPORT = 8092
const FURL = "ws://127.0.0.1:$THISPORT"


@info "Start a server with a ws handler that is unresponsive. \nClose from client side. The " *
      " close handshake aborts after $(WebSockets.TIMEOUT_CLOSEHANDSHAKE) seconds..."
server_WS = ServerWS(   HandlerFunction(req-> HTTP.Response(200)),
                        WebsocketHandler(ws-> sleep(16)))
tas = @async serve(server_WS, THISPORT)
while !istaskstarted(tas); yield(); end
sleep(1)
res = WebSockets.open((_) -> nothing, FURL);
@test res.status == 101
put!(server_WS.in, "x")

@info "Start a server with a ws handler that always reads guarded."
sleep(1)
server_WS = ServerWS(   HandlerFunction(req -> HResponse(200)),
                        WebSockets.WebsocketHandler() do req, ws_serv
                                                while isopen(ws_serv)
                                                    readguarded(ws_serv)
                                                end
                                            end);
tas = @async serve(server_WS, "127.0.0.1", THISPORT)
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

put!(server_WS.in, "x")


@info "Start a server. The wshandler use global channels for inspecting caught errors."
sleep(1)
chfromserv=Channel(2)
server_WS = ServerWS(   HandlerFunction(req-> HTTP.Response(200)),
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
tas = @async serve(server_WS, "127.0.0.1", THISPORT)
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
put!(server_WS.in, "x")
sleep(1)

@info "Start a server. Errors are output on built-in channel"
sleep(1)
global server_WS = ServerWS(   HandlerFunction(req-> HTTP.Response(200)),
                               WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                        read(ws_serv)
                                                end
                                            end);
global tas = @async serve(server_WS, "127.0.0.1", THISPORT, false)
while !istaskstarted(tas); yield(); end
sleep(3)

@info "Open a ws|client, close it out of protocol. Check server error on server.out channel."
sleep(1)
WebSockets.open((ws)-> close(ws.socket), FURL);
global err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
sleep(1)
global stack_trace = take!(server_WS.out);
if VERSION <= v"1.0.2"
    # Stack trace on master is zero. Unknown cause.
    @test length(stack_trace) in [5, 6]
end

while isready(server_WS.out)
    take!(server_WS.out)
end
sleep(1)


@info "Open ws|clients, close using every status code from RFC 6455 7.4.1\n" *
      "  Verify error messages on server.out reflect the codes."
sleep(1)
for (ke, va) in WebSockets.codeDesc
    @info "Closing ws|client with reason ", ke, " ", va
    sleep(0.3)
    WebSockets.open((ws)-> close(ws, statusnumber = ke), FURL)
    wait(server_WS.out)
    global err = take!(server_WS.out)
    @test typeof(err) <: WebSocketClosedError
    @test err.message == "ws|server respond to OPCODE_CLOSE $ke:$va"
    wait(server_WS.out)
    stacktra = take!(server_WS.out)
    if VERSION <= v"1.0.2"
        # Unknown cause, nighly behaves differently
        @test length(stacktra) == 0
    end
    while isready(server_WS.out)
        take!(server_WS.out)
    end
    sleep(1)
end

@info "Open a ws|client, close it using a status code from RFC 6455 7.4.1\n" *
      " and also a custom reason string. Verify error messages on server.out reflect the codes."

sleep(1)
global va = 1000
@info "Closing ws|client with reason", va, " ", WebSockets.codeDesc[va], " and goodbye!"
WebSockets.open((ws)-> close(ws, statusnumber = va, freereason = "goodbye!"), FURL)
wait(server_WS.out)
global err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1000:goodbye!"
global stack_trace = take!(server_WS.out)
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
global err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1006: while read(ws|client received InterruptException."
global stack_trace = take!(server_WS.out)
put!(server_WS.in, "close server")
sleep(2)
