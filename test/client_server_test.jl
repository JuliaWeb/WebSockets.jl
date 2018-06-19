# included in runtests.jl
using Test
using HTTP
using HttpServer
import WebSockets:  is_upgrade,
                    upgrade
function echows(req, ws)
    @test origin(req) == ""
    @test target(req) == "/"
    @test subprotocol(req) == ""
    while true
        data, success = readguarded(ws)
        !success && break
        !writeguarded(ws, data) && break
    end
end
                    
const port_HTTP = 8000
const port_HTTP_ServeWS = 8001
const port_HttpServer = 8081
const TCPREF = Ref{Base.TCPServer}()

# Start HTTP listen server on port $port_HTTP"
tas = @schedule HTTP.listen("127.0.0.1", port_HTTP, tcpref = TCPREF) do s
    if WebSockets.is_upgrade(s.message)
        WebSockets.upgrade(echows, s) 
    end
end
while !istaskstarted(tas);yield();end

# Start HttpServer on port $port_HttpServer
const server = Server(HttpHandler((req, res)->Response(200)), 
                      WebSocketHandler(echows));
tas = @schedule run(server, port_HttpServer)
while !istaskstarted(tas);yield();end


# Start HTTP ServerWS on port $port_HTTP_ServeWS
server_WS = WebSockets.ServerWS(
    HTTP.HandlerFunction(req-> HTTP.Response(200)), 
    WebSockets.WebsocketHandler(echows))

tas = @schedule WebSockets.serve(server_WS, "127.0.0.1", port_HTTP_ServeWS)
while !istaskstarted(tas);yield();end

const servers = [
    ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"), 
    ("HttpServer",  "ws://127.0.0.1:$(port_HttpServer)"),
    ("HTTTP ServerWS",  "ws://127.0.0.1:$(port_HTTP_ServeWS)"),
    ("ws",          "ws://echo.websocket.org"),
    ("wss",         "wss://echo.websocket.org")]

const lengths = [0, 125, 126, 127, 2000]

for (s, url) in servers, len in lengths, closestatus in [false, true]
    len == 0 && contains(url, "echo.websocket.org") && continue
    info("Testing client -> server at $(url), message length $len")
    test_str = randstring(len)
    forcecopy_str = test_str |> collect |> copy |> join
    WebSockets.open(url) do ws
        print(" -Foo-")
        write(ws, "Foo")
        @test String(read(ws)) == "Foo"
        print(" -Ping-")
        send_ping(ws)
        print(" -String length $len-\n")
        write(ws, test_str)
        @test String(read(ws)) == forcecopy_str
        closestatus && close(ws, statusnumber = 1000)
    end
    sleep(0.2)
end


# make a very simple http request for the servers with defined http handlers
resp = HTTP.request("GET", "http://127.0.0.1:$(port_HTTP_ServeWS)")
@test resp.status == 200
resp = HTTP.request("GET", "http://127.0.0.1:$(port_HttpServer)")
@test resp.status == 200

# Close the servers
close(TCPREF[])
close(server.http.sock)
put!(server_WS.in, HTTP.Servers.KILL)
