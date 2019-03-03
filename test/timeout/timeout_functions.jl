using Test
using WebSockets
import Dates.now

"Time since start"
tss() = " $(Int(round((now() - T0).value / 1000))) s "
"Server side 'websocket handler'"
function coroutine(ws)
    push!(WSLIST, ws)
    data, success = readguarded(ws)
    s = ""
    if success
        s = String(data)
        @wslog "This websocket is called ", s, " at ", tss()
        push!(WSIDLIST, s)
    else
        @wslog "Received a closing message instead of a first message", tss()
        return
    end
    try
        data = read(ws)
    catch err
        @wslog s, " was closed at ", tss(), " with message \n\t", err
        push!(CLOSINGMESSAGES, string(err))
        return
    end
    @wslog "Unexpectedly received a second message from websocket ", s, ". Now closing."
end

function gatekeeper(req, ws)
    #@info "\nOrigin: $(WebSockets.origin(req))  subprotocol: $(subprotocol(req))"
    coroutine(ws)
end

handle(req) = read("limited life websockets.html") |> WebSockets.Response

"Returns a function intended for taking a client side websocket,
a 'websocket handler'"
function clientwsh(timeout::Int)
    function wsclienthandler(ws)
        s = "$(timeout)s_timeout_Julia"
        if !writeguarded(ws, s)
            @wslog "Could not write from ", ws, " called ", s, " at",  tss()
            return
        end
        sleep(timeout)
        WebSockets.close(ws, statusnumber = 1000, freereason = "$timeout seconds are up!")
    end
end
