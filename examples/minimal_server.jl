using WebSockets
const BAREHTML = "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">
 <title>Empty.html</title></head><body></body></html>"
import Sockets
const LOCALIP = string(Sockets.getipaddr())
const PORT = 8080
const BODY =  "<body><p>Press F12
                <p>ws = new WebSocket(\"ws://$LOCALIP:$PORT\")
                <p>ws.onmessage = function(e){console.log(e.data)}
                <p>ws.send(\"Browser console says hello!\")
                </body>"

function coroutine(ws)
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        if s == ""
            writeguarded(ws, "Goodbye!")
            break
        end
        println("Received: ", s)
        writeguarded(ws, "Hello! Send empty message to exit, or just leave.")
    end
end

function gatekeeper(req, ws)
    orig = WebSockets.origin(req)
    println("\nOrigin:", orig, "    Target:", target(req), "    subprotocol:", subprotocol(req))
    if occursin(LOCALIP, orig)
        coroutine(ws)
    elseif orig == ""
        @info "Non-browser clients don't send Origin. We liberally accept the update request in this case."
        coroutine(ws)
    else
        @warn "Inacceptable request"
    end
end

handle(req) = replace(BAREHTML, "<body></body>" => BODY) |> WebSockets.Response

const server = WebSockets.ServerWS(handle,
                                    gatekeeper)

@info("Browser > $LOCALIP:$PORT , F12> console > ws = new WebSocket(\"ws://$LOCALIP:$PORT\") ")
@async WebSockets.serve(server, LOCALIP, PORT);
