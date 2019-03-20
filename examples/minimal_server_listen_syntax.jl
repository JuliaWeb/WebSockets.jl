# Minimal server using the 'listen' syntax, starting with the 'inner' functions
const BAREHTML = "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">
 <title>Empty.html</title></head><body></body></html>"
using Sockets
using WebSockets
import WebSockets.handle
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

handler(req) = replace(BAREHTML, "<body></body>" => BODY) |> WebSockets.Response
handler_wrap = WebSockets.RequestHandlerFunction(handler)

@info("Browser > $LOCALIP:$PORT , F12> console > ws = new WebSocket(\"ws://$LOCALIP:$PORT\") ")

const SERVER = Sockets.listen(Sockets.InetAddr(parse(IPAddr, LOCALIP), PORT))


task = @async try
    WebSockets.HTTP.listen(LOCALIP, PORT, server = SERVER, readtimeout = 0 ) do http
        if WebSockets.is_upgrade(http.message)
            WebSockets.upgrade(gatekeeper, http)
        else
            handle(handler_wrap, http)
        end
    end
catch err
    # Add your own error handling code; HTTP.jl sends error code to the client.
    @info err
    @info stacktrace(catch_backtrace())
end
@info("To stop serving: close(SERVER)")

nothing
