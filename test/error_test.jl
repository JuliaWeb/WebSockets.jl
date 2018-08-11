# included in runtests.jl

using Test
using Base64
import HTTP
import HttpServer: HttpHandler,
        Server
import WebSockets: ServerWS,
        serve,
        open,
        readguarded,
        writeguarded,
        WebSocketHandler,
        WebSocketClosedError,
        close


const THISPORT = 8092
URL = "ws://127.0.0.1:$THISPORT"


@info("Start a HTTP server with a ws handler that is unresponsive. Close from client side. The " *
      " close handshake aborts after $(WebSockets.TIMEOUT_CLOSEHANDSHAKE) seconds...\n")
sleep(1)
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)),
                        WebSockets.WebsocketHandler(ws-> sleep(16)))
tas = @async WebSockets.serve(server_WS, THISPORT)
while !istaskstarted(tas); yield(); end
sleep(1)
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101
put!(server_WS.in, HTTP.Servers.KILL)


@info("Start a HTTP server with a ws handler that always reads guarded.\n")
sleep(1)
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)),
                        WebSockets.WebsocketHandler() do req, ws_serv
                                                while isopen(ws_serv)
                                                    readguarded(ws_serv)
                                                end
                                            end);
tas = @async WebSockets.serve(server_WS, "127.0.0.1", THISPORT)
while !istaskstarted(tas); yield(); end
sleep(1)

@info("Attempt to read guarded from a closing ws|client. Check for return false.\n")
sleep(1)
WebSockets.open(URL) do ws_client
        close(ws_client)
        @test (UInt8[], false) == readguarded(ws_client)
    end;
sleep(1)


@info("Attempt to write guarded from a closing ws|client. Check for return false.\n")
sleep(1)
WebSockets.open(URL) do ws_client
    close(ws_client)
    @test false == writeguarded(ws_client, "writethis")
end;
sleep(1)


@info("Attempt to read from closing ws|client. Check caught error.\n")
sleep(1)
try
    WebSockets.open(URL) do ws_client
        close(ws_client)
        read(ws_client)
    end
catch err
    @test typeof(err) <: ErrorException
    @test err.msg == "Attempt to read from closed WebSocket|client. First isopen(ws), or use readguarded(ws)!"
end
sleep(1)


@info("Attempt to write to a closing ws|client (this takes some time, there is no check
      in WebSockets against it). Check caught error.\n")
sleep(1)
try
    WebSockets.open(URL) do ws_client
        close(ws_client)
        write(ws_client, "writethis")
    end
catch err
     @test typeof(err) <: HTTP.IOExtras.IOError
end

put!(server_WS.in, HTTP.Servers.KILL)


@info("\n\nStart a HttpServer\n")
sleep(1)
server = Server(HttpHandler() do req, res
                    Response(200)
                end,
                WebSocketHandler() do req, ws_serv
                    while isopen(ws_serv)
                        readguarded(ws_serv)
                    end
                end)
tas = @async run(server, THISPORT)
while !istaskstarted(tas);yield();end
sleep(3)
@info("Attempt to write to a closing ws|client, served by HttpServer (this takes some time, there is no check
      in WebSockets against it). Check caught error.")
try
    WebSockets.open(URL) do ws_client
        close(ws_client)
        write(ws_client, "writethis")
    end
catch err
     @test typeof(err) <: HTTP.IOExtras.IOError
end
close(server)
sleep(1)


@info("\nStart an async HTTP server. The wshandler use global channels for inspecting caught errors.\n")
sleep(1)
chfromserv=Channel(2)
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)),
                        WebSockets.WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                    try
                                                        read(ws_serv)
                                                    catch err
                                                        put!(chfromserv, err)
                                                        put!(chfromserv, stacktrace(catch_backtrace())[1:2])
                                                    end
                                                end
                                            end);
tas = @async WebSockets.serve(server_WS, "127.0.0.1", THISPORT)
while !istaskstarted(tas); yield(); end
sleep(3)

@info("Open a ws|client, close it out of protocol. Check server error on channel.\n")
res = WebSockets.open((ws)-> close(ws.socket), URL)
@test res.status == 101
sleep(1)
err = take!(chfromserv)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
stack_trace = take!(chfromserv)
@test length(stack_trace) == 2
put!(server_WS.in, HTTP.Servers.KILL)
sleep(1)

@info("\nStart an async HTTP server. Errors are output on built-in channel\n")
sleep(1)
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)),
                        WebSockets.WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                        read(ws_serv)
                                                end
                                            end);
tas = @async WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
while !istaskstarted(tas); yield(); end
sleep(3)

@info("Open a ws|client, close it out of protocol. Check server error on server.out channel.\n")
sleep(1)
WebSockets.open((ws)-> close(ws.socket), URL);
err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
stack_trace = take!(server_WS.out);
@test length(stack_trace) == 6

while isready(server_WS.out)
    take!(server_WS.out)
end
sleep(1)


@info("Open ws|clients, close using every status code from RFC 6455 7.4.1\n" *
      "  Verify error messages on server.out reflect the codes.")
sleep(1)
for (ke, va) in WebSockets.codeDesc
    @info("Closing ws|client with reason ", ke, " ", va)
    sleep(0.3)
    WebSockets.open((ws)-> close(ws, statusnumber = ke), URL)
    wait(server_WS.out)
    err = take!(server_WS.out)
    @test typeof(err) <: WebSocketClosedError
    @test err.message == "ws|server respond to OPCODE_CLOSE $ke:$va"
    wait(server_WS.out)
    stacktra = take!(server_WS.out)
    @test length(stacktra) == 0
    while isready(server_WS.out)
        take!(server_WS.out)
    end
    sleep(1)
end

@info("Open a ws|client, close it using a status code from RFC 6455 7.4.1\n" *
      " and also a custom reason string. Verify error messages on server.out reflect the codes.")

sleep(1)
va = 1000
@info("Closing ws|client with reason", va, " ", WebSockets.codeDesc[va], " and goodbye!")
WebSockets.open((ws)-> close(ws, statusnumber = va, freereason = "goodbye!"), URL)
wait(server_WS.out)
err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1000:goodbye!"
stack_trace = take!(server_WS.out)
sleep(1)


@info("\nOpen a ws|client. Throw an InterruptException to it. Check that the ws|server\n " *
    "error shows the reason for the close.\n " *
    "A lot of error text will spill over into REPL, but the test is unaffected\n\n")
sleep(1)
function selfinterruptinghandler(ws)
    task = @async WebSockets.open((ws)-> read(ws), URL)
    sleep(3)
    @async Base.throwto(task, InterruptException())
    sleep(1)
    nothing
end
WebSockets.open(selfinterruptinghandler, URL)
sleep(6)
err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1006: while read(ws|client received InterruptException."
stack_trace = take!(server_WS.out)
put!(server_WS.in, HTTP.Servers.KILL)
sleep(2)
