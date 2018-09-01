# Minimal server using the 'listen' syntax, using the anonymous function 'do' syntax.
const BAREHTML = "<head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">
 <title>Empty.html</title></head><body></body></html>"
import Sockets
using WebSockets
import HTTP.listen
import HTTP.Servers.handle_request
const LOCALIP = string(Sockets.getipaddr())
const PORT = 8080
const BODY =  "<body><p>Press F12
                <p>ws = new WebSocket(\"ws://$LOCALIP:$PORT\")
                <p>ws.onmessage = function(e){console.log(e.data)}
                <p>ws.send(\"Browser console says hello!\")
                </body>"

global TCPREF = Ref{Base.IOServer}()
@info("Browser > $LOCALIP:$PORT , F12> console > ws = new WebSocket(\"ws://$LOCALIP:$PORT\") ")
try
    listen(LOCALIP, UInt16(PORT), tcpref = TCPREF) do http
        if WebSockets.is_upgrade(http.message)
            WebSockets.upgrade(http) do req, ws
                orig = WebSockets.origin(req)
                println("\nOrigin:", orig, "    Target:", target(req), "    subprotocol:", subprotocol(req))
                if occursin(LOCALIP, orig)
                    coroutine(ws)
                elseif orig == ""
                    @info "Non-browser clients don't send Origin. We liberally accept the update request in this case."
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
                else
                    @warn "Inacceptable request"
                end
            end
        else
            handle_request(http) do req
                replace(BAREHTML, "<body></body>" => BODY) |> WebSockets.Response
            end
        end
    end
catch err
    # Add your own error handling code; HTTP.jl sends error code to the client.
    @info err
    @info stacktrace(catch_backtrace())[1:4]
end
nothing
