#=

A chat server application. Starts a new task for each browser (tab) that connects.

To use:
    - include("chat_explore.jl") in REPL
    - start a browser on the local ip address, e.g.: http://192.168.0.4:8080
    - inspect global variables starting with 'last' while the chat is running asyncronously

To call in from other devices, figure out your IP address on the network and change the 'gatekeeper' code.

Functions used as arguments are explicitly defined with names instead of anonymous functions (do..end constructs).
This may improve debugging readability at the cost of increased verbosity.

=#
global lastreq = 0
global lastws = 0
global lastmsg = 0
global lastws = 0
global lastserver = 0

using WebSockets
import WebSockets:Response,
                  Request,
                  HandlerFunction,
                  WebsocketHandler
using Dates
import Sockets
const CLOSEAFTER = Dates.Second(1800)
const HTTPPORT = 8080
const LOCALIP = string(Sockets.getipaddr())
const USERNAMES = Dict{String, WebSocket}()
const HTMLSTRING = read(joinpath(@__DIR__, "chat_explore.html"), String)


# Since we are to access a websocket from outside
# it's own websocket handler coroutine, we need some kind of
# mutable container for storing references:
const WEBSOCKETS = Dict{WebSocket, Int}()

"""
Called by 'gatekeeper', this function will be running in a task while the
particular websocket is open. The argument is an open websocket.
Other instances of the function run in other tasks.
"""
function coroutine(thisws)
    global lastws = thisws
    push!(WEBSOCKETS, thisws => length(WEBSOCKETS) +1 )
    t1 = now() + CLOSEAFTER
    username = ""
    while now() < t1
        # This next call waits for a message to
        # appear on the socket. If there is none,
        # this task yields to other tasks.
        data, success = readguarded(thisws)
        !success && break
        global lastmsg = msg = String(data)
        print("Received: $msg ")
        if username == ""
            username = approvedusername(msg, thisws)
            if username != ""
                println("from new user $username ")
                !writeguarded(thisws, username) && break
                println("Tell everybody about $username")
                foreach(keys(WEBSOCKETS)) do ws
                    writeguarded(ws, username * " enters chat")
                end
            else
                println(", username taken!")
                !writeguarded(thisws, "Username taken!") && break
            end
        else
            println("from $username ")
            distributemsg(username * ": " * msg, thisws)
            startswith(msg, "exit") && break
        end
    end
    exitmsg = username == "" ? "unknown" : username * " has left"
    distributemsg(exitmsg, thisws)
    println(exitmsg)
    # No need to close the websocket. Just clean up external references:
    removereferences(thisws)
    nothing
end

function removereferences(ws)
    haskey(WEBSOCKETS, ws) && pop!(WEBSOCKETS, ws)
    for (discardname, wsref) in USERNAMES
        if wsref === ws
            pop!(USERNAMES, discardname)
            break
        end
    end
    nothing
end


function approvedusername(msg, ws)
    !startswith(msg, "userName:") && return ""
    newname = msg[length("userName:") + 1:end]
    newname =="" && return ""
    haskey(USERNAMES, newname) && return ""
    push!(USERNAMES, newname => ws)
    newname
end


function distributemsg(msgout, not_to_ws)
    foreach(keys(WEBSOCKETS)) do ws
        if ws !== not_to_ws
            writeguarded(ws, msgout)
        end
    end
    nothing
end


"""
`Server => gatekeeper(Request, WebSocket) => coroutine(WebSocket)`

The gatekeeper makes it a little harder to connect with
malicious code. It inspects the request that was upgraded
to a a websocket.
"""
function gatekeeper(req, ws)
    global lastreq = req
    global lastws = ws
    orig = WebSockets.origin(req)
    if occursin(LOCALIP, orig)
        coroutine(ws)
    else
        @warn("Unauthorized websocket connection, $orig not approved by gatekeeper, expected $LOCALIP")
    end
    nothing
end

"Request to response. Response is the predefined HTML page with some javascript"
req2resp(req::Request) = HTMLSTRING |> Response

# The server takes two function wrappers; one handler function for page requests,
# one for opening websockets (which the javascript in the HTML page will try to do)
global lastserver = WebSockets.ServerWS(HandlerFunction(req2resp), WebsocketHandler(gatekeeper))

# Start the server asyncronously, and stop it later
global litas = @async WebSockets.serve(lastserver, LOCALIP, HTTPPORT)
@async begin
    println("HTTP server listening on $LOCALIP:$HTTPPORT for $CLOSEAFTER")
    sleep(CLOSEAFTER.value)
    println("Time out, closing down $HTTPPORT")
    Base.throwto(litas, InterruptException())
    # Alternative close method: see ?WebSockets.serve
end


nothing
