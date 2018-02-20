using HTTP
using HttpServer
using WebSockets
using Base.Test

@testset "HTTP" begin

port_HTTP = 8000
port_HttpServer = 8081

info("Start HTTP server on port $(port_HTTP)")
@async HTTP.listen("127.0.0.1",UInt16(port_HTTP)) do http
    if WebSockets.is_upgrade(http.message)
        WebSockets.upgrade(http) do ws
            while !eof(ws)
                data = String(read(ws))
                write(ws,data)
            end
        end
    end
end

info("Start HttpServer on port $(port_HttpServer)")
wsh = WebSocketHandler() do req,ws
    while !eof(ws)
        msg = String(read(ws))
        write(ws, msg)
    end
end
server = Server(wsh)
@async run(server,port_HttpServer)

sleep(2)

servers = [
    ("ws",          "ws://echo.websocket.org"),
    ("wss",         "wss://echo.websocket.org"),
    ("HTTP",        "ws://127.0.0.1:$(port_HTTP)"), 
    ("HttpServer",  "ws://127.0.0.1:$(port_HttpServer)")]

for (s, url) in servers
    info("Testing local $(s) server at $(url)...")
    WebSockets.open(url) do ws
        write(ws, "Foo")
        @test String(read(ws)) == "Foo"
    
        write(ws, "Bar")
        @test String(read(ws)) == "Bar"
    
        send_ping(ws)
        read(ws)
    end
end

end # testset