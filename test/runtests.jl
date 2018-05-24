using HTTP
using HttpServer
using WebSockets
using Base.Test

@testset "HTTP" begin

const port_HTTP = 8000
const port_HttpServer = 8081

info("Start HTTP server on port $(port_HTTP)")

function echows(ws)
    while true
        data, success = readguarded(ws)
        !success && break
        !writeguarded(ws, data) && break
    end
end

@async HTTP.listen("127.0.0.1", UInt16(port_HTTP)) do http
    if WebSockets.is_upgrade(http.message)
        WebSockets.upgrade(echows, http) 
    end
end

info("Start HttpServer on port $(port_HttpServer)")
wsh = WebSocketHandler() do req, ws
    echows(ws) 
end
server = Server(wsh)
@async run(server,port_HttpServer)

sleep(4)

servers = [
    ("ws",          "ws://echo.websocket.org"),
    ("wss",         "wss://echo.websocket.org"),
    ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"), 
    ("HttpServer",  "ws://127.0.0.1:$(port_HttpServer)")]

for (s, url) in servers
    info("Testing ws client connecting to $(s) server at $(url)...")
    WebSockets.open(url) do ws
        print(" -Foo-")
        write(ws, "Foo")
        @test String(read(ws)) == "Foo"
        print(" -Ping-")
        send_ping(ws)
        println(" -Bar-")
        write(ws, "Bar")
        @test String(read(ws)) == "Bar"
        sleep(1)
    end
    sleep(1)
end

end # testset