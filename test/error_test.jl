# included in runtests.jl
using Test
using WebSockets
import WebSockets:HTTP,
       base64encode,
       throwto,
       OPCODE_TEXT,
       locked_write
import Base.BufferStream
include("client_server_functions.jl")
const FURL = "ws://127.0.0.1"
const FPORT = 8092

@info "Start a server with a ws handler that is unresponsive. \nClose from client side. The " *
      " close handshake aborts after $(WebSockets.TIMEOUT_CLOSEHANDSHAKE) seconds..."
s = WebSockets.ServerWS(
    req::HTTP.Request -> HTTP.Response(200),
    (req::HTTP.Request, ws::WebSocket) -> begin
        for i=1:16
            sleep(1)
            i < 11 && println(i)
        end
        return
    end)

startserver(s, url=SURL, port=FPORT)

res = WebSockets.open((_) -> nothing, "$(FURL):$(FPORT)");
@test res.status == 101
close(s)

@info "Start a server with a ws handler that always reads guarded."
sleep(1)
s = WebSockets.ServerWS(
    req -> HTTP.Response(200),
    (req, ws_serv) -> begin
        while isopen(ws_serv)
            WebSockets.readguarded(ws_serv)
        end
    end);
startserver(s, url=SURL, port=FPORT)
sleep(1)

@info "Attempt to read guarded from a closing ws|client. Check for return false."
sleep(1)
WebSockets.open("$(FURL):$(FPORT)") do ws_client
        close(ws_client)
        data = WebSockets.readguarded(ws_client)
        @test (UInt8[], false) == data
    end;
sleep(1)


@info "Attempt to write guarded from a closing ws|client. Check for return false."
sleep(1)
WebSockets.open("$(FURL):$(FPORT)") do ws_client
    close(ws_client)
    data = WebSockets.writeguarded(ws_client, "writethis")
    @test false == data
end;
sleep(1)


@info "Attempt to read from closing ws|client. Check caught error."
sleep(1)
try
    WebSockets.open("$(FURL):$(FPORT)") do ws_client
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
    WebSockets.open("$(FURL):$(FPORT)") do ws_client
        close(ws_client)
        write(ws_client, "writethis")
    end
catch err
    show(err)
     @test typeof(err) <: WebSocketClosedError
     @test err.message == " while open ws|client: stream is closed or unusable"
end

close(s)

@info "Start a server. The wshandler use global channels for inspecting caught errors."
sleep(1)
chfromserv=Channel(2)
s = WebSockets.ServerWS(
    req-> HTTP.Response(200),
    ws_serv->begin
        while isopen(ws_serv)
            try
                read(ws_serv)
            catch err
                put!(chfromserv, err)
                put!(chfromserv, stacktrace(catch_backtrace())[1:2])
            end
        end
    end);
startserver(s, url=SURL, port=FPORT)
sleep(3)

@info "Open a ws|client, close it out of protocol. Check server error on channel."
global res = WebSockets.open((ws)-> close(ws.socket), "$(FURL):$(FPORT)")
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

close(s)

sleep(1)

@info "Start a server. Errors are output on built-in channel"
sleep(1)
s = WebSockets.ServerWS(
    req-> HTTP.Response(200),
    ws_serv->begin
        while isopen(ws_serv)
                read(ws_serv)
        end
    end);
startserver(s, url=SURL, port=FPORT)
sleep(3)

@info "Open a ws|client, close it out of protocol. Check server error on server.out channel."
sleep(1)
WebSockets.open((ws)-> close(ws.socket), "$(FURL):$(FPORT)");
global err = take!(s.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
sleep(1)
global stack_trace = take!(s.out);
if VERSION <= v"1.0.2"
    # Stack trace on master is zero. Unknown cause.
    @test length(stack_trace) in [5, 6]
end

while isready(s.out)
    take!(s.out)
end


close(s)
startserver(s, url=SURL, port=FPORT)
sleep(3)

@info "Open ws|clients, close using every status code from RFC 6455 7.4.1\n" *
      "  Verify error messages on server.out reflect the codes."
sleep(1)
for (ke, va) in WebSockets.codeDesc
    @info "Closing ws|client with reason ", ke, " ", va
    sleep(0.3)
    WebSockets.open((ws)-> close(ws, statusnumber = ke), "$(FURL):$(FPORT)")
    wait(s.out)
    global err = take!(s.out)
    @test typeof(err) <: WebSocketClosedError
    @test err.message == "ws|server respond to OPCODE_CLOSE $ke:$va"
    wait(s.out)
    stacktra = take!(s.out)
    if VERSION <= v"1.0.2"
        # Unknown cause, nighly behaves differently
        @test length(stacktra) == 0
    end
    while isready(s.out)
        take!(s.out)
    end
    sleep(1)
end

@info "Open a ws|client, close it using a status code from RFC 6455 7.4.1\n" *
      " and also a custom reason string. Verify error messages on server.out reflect the codes."

sleep(1)
global va = 1000
@info "Closing ws|client with reason", va, " ", WebSockets.codeDesc[va], " and goodbye!"
WebSockets.open((ws)-> close(ws, statusnumber = va, freereason = "goodbye!"), "$(FURL):$(FPORT)")
wait(s.out)
global err = take!(s.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1000:goodbye!"
global stack_trace = take!(s.out)
sleep(1)

@info "Open a ws|client. Throw an InterruptException to it. Check that the ws|server\n " *
    "error shows the reason for the close."
sleep(1)
function selfinterruptinghandler(ws)
    task = @async WebSockets.open((ws)-> read(ws), "$(FURL):$(FPORT)")
    sleep(3)
    @async Base.throwto(task, InterruptException())
    sleep(1)
    nothing
end
WebSockets.open(selfinterruptinghandler, "$(FURL):$(FPORT)")
sleep(6)
global err = take!(s.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1006: while read(ws|client received InterruptException."
global stack_trace = take!(s.out)

close(s)

@info "Trigger check_upgrade WebSocketErrors "
let noupgrade, noconnectionupgrade, key
    key = base64encode(rand(UInt8, 16))
    noupgrade = WebSockets.Request("GET", "/", [
                    "Connection" => "Upgrade",
                    "Sec-WebSocket-Key" => key,
                    "Sec-WebSocket-Version" => "13"
                ])
    @test_throws WebSockets.WebSocketError WebSockets.check_upgrade(noupgrade)
    noconnectionupgrade = WebSockets.Request("GET", "/", [
                        "Upgrade" => "websocket",
                        "Sec-WebSocket-Key" => key,
                        "Sec-WebSocket-Version" => "13"
                ])
    @test_throws WebSockets.WebSocketError WebSockets.check_upgrade(noconnectionupgrade)
end

sleep(2)
