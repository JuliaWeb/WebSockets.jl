using WebSockets
import WebSockets:Response,
                  Request
using Dates
using Sockets

global LASTREQ = 0
global LASTWS = 0
global LASTMSG = 0
global LASTSERVER = 0

const CLOSEAFTER = Dates.Second(1800)
const HTTPPORT = 8080
const LOCALIP = string(Sockets.getipaddr())
const USERNAMES = Dict{String, WebSocket}()
const HTMLSTRING = read(joinpath(@__DIR__, "chat_explore.html"), String)


@info """
A chat server application. For each browser (tab) that connects,
an 'asyncronous function' aka 'coroutine' aka 'task' is started.

To use:
    - include("chat_explore.jl") in REPL
    - start a browser on the local ip address, e.g.: http://192.168.0.4:8080
    - inspect global variables starting with 'LAST' while the chat is running asyncronously 

"""

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
        global LASTMSG = msg = String(data)
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
    global LASTREQ = req
    global LASTWS = ws
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


# The following lines disblle detail messages from spilling into the
# REPL. Remove the it to gain insight.
using Logging
import Logging.shouldlog
function shouldlog(::ConsoleLogger, level, _module, group, id)
    if _module == WebSockets.HTTP.Servers
        if level == Logging.Warn || level == Logging.Info
            return false
        else
            return true
        end
    else
        return true
    end
end

# ServerWS takes two functions; the first a http request handler function for page requests,
# one for opening websockets (which javascript in the HTML page will try to do)
global LASTSERVER = WebSockets.ServerWS(req2resp, gatekeeper)

# Start the server asyncronously, and stop it later
@async WebSockets.serve(LASTSERVER, LOCALIP, HTTPPORT)
@async begin
    println("HTTP server listening on $LOCALIP:$HTTPPORT for $CLOSEAFTER")
    sleep(CLOSEAFTER.value)
    println("Time out, closing down $HTTPPORT")
    put!(LASTSERVER.in, "I can send anything, you close")
    nothing
end
# for inspecting in REPL or Atom / Juno - update after starting some clients.
LASTWS
LASTSERVER.out
WEBSOCKETS
#take!(LASTSERVER.out)|>string
nothing
