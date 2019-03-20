using Test
using WebSockets
import Dates.now

"Time since start"
tss() = " $(Int(round((now() - T0).value / 1000))) s "
"Server side 'websocket handler'"
function coroutine(ws)
    sttim = time_ns()
    push!(WSLIST, sttim => ws)
    data, success = readguarded(ws)
    s = ""
    if success
        s = String(data)
        @wslog "This websocket is called ", s, " at ", tss()
        push!(WSIDLIST, sttim => s)
    else
        @wslog "Received a closing message instead of a first message", tss()
        return
    end
    try
        data = read(ws)
    catch err
        @wslog s, " was closed at ", tss(), " with message \n\t", err
        push!(CLOSINGMESSAGES, sttim => string(err))
        return
    end
    @wslog "Unexpectedly received a second message from websocket ", s, ". Now closing."
end

function gatekeeper(req, ws)
    #@info "\nOrigin: $(WebSockets.origin(req))  subprotocol: $(subprotocol(req))"
    coroutine(ws)
end

handle(req) = read("limited life websockets.html") |> WebSockets.HTTP.Response

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
function checktasks()
    count = 0
    for clita in CLIENTTASKS
        count +=1
        if clita[2].state == :failed
            @error "Client websocket task ", clita[1], " => " clita[2] , " failed"
        end
    end
    count
end
