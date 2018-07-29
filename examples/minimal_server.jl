using HttpServer
using WebSockets

function coroutine(ws)
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        s == "" && break
        println("Received: ", s)
        if s[1] == "P"
            writeguarded(ws, "No, I'm not!")
        else
            writeguarded(ws, "Why?")
        end
    end
end

function gatekeeper(req, ws)
    println("\nOrigin:", origin(req), "    Target:", target(req), "    subprotocol:", subprotocol(req))
    # Non-browser clients don't send Origin. We liberally accept in this case.
    if origin(req) == "" || origin(req) == "http://127.0.0.1:8080" || origin(req) == "http://localhost:8080"
        coroutine(ws)
    else
        println("Inacceptable request")
    end
end

handle(req, res) = Response(200)

server = Server(HttpHandler(handle), 
                WebSocketHandler(gatekeeper))
@info("Browser > http://127.0.0.1:8080 , F12> console > ws = new WebSocket(\"ws://127.0.0.1:8080\") ")
@async run(server, 8080)
