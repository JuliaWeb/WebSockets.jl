# included in runtests.jl

using Base.Test
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

info("Start a HTTP server with a ws handler that is unresponsive. Close from client side. The
      close handshake aborts after $(WebSockets.TIMEOUT_CLOSEHANDSHAKE) seconds...")
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)), 
                        WebSockets.WebsocketHandler(ws-> sleep(16)))
tas = @schedule WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
while !istaskstarted(tas); yield(); end
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101
put!(server_WS.in, HTTP.Servers.KILL)
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)), 
                        WebSockets.WebsocketHandler() do req, ws_serv
                                                while isopen(ws_serv)
                                                    readguarded(ws_serv)
                                                end
                                            end);
tas = @schedule WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
while !istaskstarted(tas); yield(); end
sleep(1)
# attempt to read guarded from closed websocket
WebSockets.open(URL) do ws_client
        close(ws_client)
        @test (UInt8[], false) == readguarded(ws_client) 
    end;
sleep(1)

# attempt to write guarded to closed websocket
WebSockets.open(URL) do ws_client
    close(ws_client)
    @test false == writeguarded(ws_client, "writethis") 
end;
sleep(1)

# attempt to read from closed websocket
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


info("Attempt to write to a closed websocket, served by HttpServer (this takes some time, there is no check
      in WebSockets against it")
try 
    WebSockets.open(URL) do ws_client
        close(ws_client)
        write(ws_client, "writethis") 
    end
catch err
     @test typeof(err) <: HTTP.IOExtras.IOError
end

put!(server_WS.in, HTTP.Servers.KILL)


# Start a HttpServer
server = Server(HttpHandler() do req, res
                    Response(200)
                end,
                WebSocketHandler() do req, ws_serv
                    while isopen(ws_serv)
                        readguarded(ws_serv)
                    end
                end) 
tas = @schedule run(server, THISPORT)
while !istaskstarted(tas)
    yield()
end
sleep(3)
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

# Capture ws|server handler errors in user's handler while async. 
# This debug info might otherwise get lost when using listen(..) directly.
chfromserv=Channel(2)
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)), 
                        WebSockets.WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                    try
                                                        read(ws_serv)
                                                    catch err
                                                        put!(chfromserv, err)
                                                        put!(chfromserv, catch_stacktrace()[1:2])
                                                    end
                                                end
                                            end);
sleep(3)

tas = @schedule WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
while !istaskstarted(tas); yield(); end
sleep(1)
res = WebSockets.open((ws)-> close(ws.socket), URL)
@test res.status == 101
sleep(1)
wait(chfromserv)
err = take!(chfromserv)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
wait(chfromserv)
stack_trace = take!(chfromserv)
@test length(stack_trace) == 2
put!(server_WS.in, HTTP.Servers.KILL)
sleep(1)

# Capture ws|server side error "automatically"
server_WS = ServerWS(   HTTP.HandlerFunction(req-> HTTP.Response(200)), 
                        WebSockets.WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                        read(ws_serv)
                                                end
                                            end);
tas = @schedule WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
while !istaskstarted(tas); yield(); end
sleep(3)

# Close out of protocol
WebSockets.open((ws)-> close(ws.socket), URL);
sleep(1)
wait(server_WS.out)
err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == " while read(ws|server) BoundsError(UInt8[], (1,))"
wait(server_WS.out)
stack_trace = take!(server_WS.out);
@test length(stack_trace) == 6


while isready(server_WS.out)
    take!(server_WS.out)
end
sleep(1)

# Close using Status codes according to RFC 6455 7.4.1
for (ke, va) in WebSockets.codeDesc
    info("Closing ws|client with reason ", ke, " ", va)
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

# Close with a given reason
va = 1000
info("Closing ws|client with reason", va, " ", WebSockets.codeDesc[va], " and goodbye!")
WebSockets.open((ws)-> close(ws, statusnumber = 1000, freereason = "goodbye!"), URL)
wait(server_WS.out)
err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1000:goodbye!"
stack_trace = take!(server_WS.out)
sleep(1)

println()
info(" React to an InterruptException with a closing handshake.
     A lot of error text will spill over into REPL, but the test is unaffected")
println()

function selfinterruptinghandler(ws)
    task = @schedule WebSockets.open((ws)-> read(ws), URL)
    sleep(3)
    @schedule Base.throwto(task, InterruptException())
    sleep(1)
    nothing
end
WebSockets.open(selfinterruptinghandler, URL)
sleep(6)
wait(server_WS.out)
err = take!(server_WS.out)
@test typeof(err) <: WebSocketClosedError
@test err.message == "ws|server respond to OPCODE_CLOSE 1006: while read(ws|client received InterruptException."
wait(server_WS.out)
stack_trace = take!(server_WS.out)
put!(server_WS.in, HTTP.Servers.KILL)
sleep(1)
