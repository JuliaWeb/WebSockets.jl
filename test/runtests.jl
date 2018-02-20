using HTTP
using HttpServer
using WebSockets
using Base.Test

port_HTTP = 8000
port_HttpServer = 8081

@testset "HTTP" begin

info("Testing ws...")
WebSockets.open("ws://echo.websocket.org") do ws
    write(ws, "Foo")
    @test String(read(ws)) == "Foo"

    close(ws)
end
sleep(1)

info("Testing wss...")
WebSockets.open("wss://echo.websocket.org") do ws
    write(ws, "Foo")
    @test String(read(ws)) == "Foo"

    close(ws)
end
sleep(1)

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

info("Testing local HTTP server...")
WebSockets.open("ws://127.0.0.1:$(port_HTTP)") do ws
    write(ws, "Foo")
    @test String(read(ws)) == "Foo"

    write(ws, "Bar")
    @test String(read(ws)) == "Bar"

    send_ping(ws)
    read(ws)
end

info("Testing local HttpServer...")
WebSockets.open("ws://127.0.0.1:$(port_HttpServer)") do ws
    write(ws, "Foo")
    @test String(read(ws)) == "Foo"

    write(ws, "Bar")
    @test String(read(ws)) == "Bar"

    send_ping(ws)
    read(ws)
end

servers = ["HTTP", "HttpServer"]

for s in servers
    url = "ws://127.0.0.1:$(eval(Symbol("port_$(s)")))"
    info("Testing local $(s) server at $(url)...")
    WebSockets.open(url) do ws
        println("New WebSocket")
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
        write(ws, "Foo")
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
        @test String(read(ws)) == "Foo"
    
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
        write(ws, "Bar")
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
        @test String(read(ws)) == "Bar"
        
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
        send_ping(ws)
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
        read(ws)
        sleep(1);println("Bytes: $(nb_available(ws.socket))")
    end
end

end # testset