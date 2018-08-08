using HTTP
using WebSockets

function coroutine(ws)
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        if s == ""
            break
        end
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

handle(req, res) = HTTP.Response(200)

server = WebSockets.ServerWS(HTTP.HandlerFunction(handle), 
                WebSockets.WebsocketHandler(gatekeeper))

@info("Browser > http://127.0.0.1:8080 , F12> console > ws = new WebSocket(\"ws://127.0.0.1:8080\") ")
@async WebSockets.serve(server, 8080)
