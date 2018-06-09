using HttpServer
using WebSockets

function coroutine(ws)
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        if s == ""
            break
        end
        println(s)
        if s[1] == "P"
            writeguarded(ws, "No, I'm not!")
        else
            writeguarded(ws, "Why?")
        end
    end
end

function gatekeeper(req, ws)
    if origin(req) == "http://127.0.0.1:8080" || origin(req) == "http://localhost:8080"
        coroutine(ws)
    else
        println(origin(req))
    end
end

handle(req, res) = Response(200)

server = Server(HttpHandler(handle), 
                WebSocketHandler(gatekeeper))

@async run(server, 8080)
