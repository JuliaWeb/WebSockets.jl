using HTTP
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

handle(req, res) = HTTP.Response(200)

server = WebSockets.ServerWS(HTTP.HandlerFunction(handle), 
                WebSockets.WebsocketHandler(gatekeeper))

@async WebSockets.serve(server, 8080)
