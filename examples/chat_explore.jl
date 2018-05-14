#=
Difference to chat-client:
This example declares global variables and use duck typing on 
them. Their types will change.
The aim is that you can examine types in the REPL while running the
example. The aim is NOT that you can expect clean exits. We don't
release all the references after you close connections.

Function containers are explicitly defined with names. Although
anonymous functions may be more commonly used in the web domain,
named functions may improve error message readability.

=#

# TODO fix errors and style

# Globals, where used in functions will change the type
global lastreq = 0
global lastreqheadersdict = 0
global lastws= 0
global lastwsHTTP = 0
global lastdata= 0
global lastmsg= 0
global lasthttp= 0
global lastws= 0
global laste= 0
global lasthttp= 0

using HttpServer
using HTTP
using WebSockets
const CLOSEAFTER = Base.Dates.Second(1800)
const HTTPPORT = 8080
const PORT_OLDTYPE = 8000
const USERNAMES = Dict{String, WebSocket}()
const WEBSOCKETS = Dict{WebSocket, Int}()


#=
low level functions, works on old and new type.
=#
function removereferences(ws)
    ws in keys(WEBSOCKETS) && pop!(WEBSOCKETS, ws)
    for (discardname, wsref) in USERNAMES
        if wsref === ws
            pop!(USERNAMES, discardname)
            break
        end
    end
    nothing
end

function process_error(id, e)
    if typeof(e) == InterruptException
        info(id, "Received exit order.")
    elseif typeof(e) == ArgumentError
        info(id, typeof(e), "\t", e.msg)
    elseif typeof(e) == ErrorException
        info(id, typeof(e), "\t", e.msg)
    else
        if :msg in fieldnames(e) && e.msg == "Attempt to read from closed WebSocket"
            warn(id, typeof(e), "\t", e.msg)
        else
            warn(id, e, "\nStacktrace:", stacktrace(true))
        end
    end 
end

function protectedwrite(ws, msg)
    global laste
    try
        write(ws, msg)
    catch e
        laste = e
        process_error("chat_explore.protectedwrite: ", e)
        removereferences(ws)
        return false
    end
    true
end

function protectedread(ws)
    global laste
    global lastdata
    data = Vector{UInt8}()
    contflag = true
    try
        data = read(ws)
        lastdata = data
    catch e
        laste = e
        contflag = false
        process_error("chat_explore.protectedread: ", e)
    finally
        return data, contflag
    end
end



function findusername(msg, ws)
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
            protectedwrite(ws, msgout)
        end
    end
    nothing
end

function wsfunc(thisws)
    global lastws
    global lastmsg
    lastws = thisws
    push!(WEBSOCKETS, thisws => length(WEBSOCKETS) +1 )
    contflag = true
    t0 = now()
    data = Vector{UInt8}()
    msg = ""
    username = ""
    changedname = false
    while now()-t0 < CLOSEAFTER && contflag
        data, contflag = protectedread(thisws)
        if contflag
            msg = String(data)
            lastmsg = msg
            println("Received: $msg")
            if username == ""  
                username = findusername(msg, thisws)
                if username != ""
                    if !protectedwrite(thisws, username) 
                        contflag = false
                    end
                    println("Tell everybody about $username")
                    foreach(keys(WEBSOCKETS)) do ws
                        protectedwrite(ws, username * " enters chat")
                    end
                else
                    println("Username taken!")
                    if !protectedwrite(thisws, "Username taken!")
                        contflag = false
                    end
                end 
            else
                contflag = !startswith(msg, "exit")
                contflag || println("Received exit message. Closing.")
            end
        end
    end
    exitusername = username == "" ? "unknown" : username
    distributemsg(exitusername * " has left", thisws)
    removereferences(thisws)
    # It's not this functions responsibility to close the websocket. Just to forget about it.
    nothing
end



#=
Functions for old type i.e. HttpServer based connections.
This function is called after handshake, and after
subprotocol is checked against a list of user supported subprotocols. 
=#
function gatekeeper_oldtype(req, ws)
    global lastreq
    global lastws
    lastreq = req
    lastws = ws
    # Here we can pick between functions 
    # based on e.g.
    # 	if haskey(req.headers,"Sec-WebSocket-Protocol")
    #
     wsfunc(ws)
end


# Just for easy REPL inspection, we'll declare the handler object explicitly.
# With handler we mean an instance of a structure with at least one function reference.
handler_ws_oldtype = WebSocketHandler(gatekeeper_oldtype)
# explicit http server handlers
httpfunc_oldtype(req, res) = readstring(Pkg.dir("WebSockets","examples","chat_explore.html")) |> Response
handler_http_oldtype = HttpHandler(httpfunc_oldtype)
# define both in one server. We could call this a handler, too, since it's just a
# bigger function structure. Or we may call it an object.
server_def_oldtype = Server(handler_http_oldtype, handler_ws_oldtype )

#=
 Now we'll run an external program which starts
 the necessary tasks on Julia.
 We can run this async, which might be considered
 bad pracice and leads to more bad connections.
 For debugging and building programs, it's gold to run this async.
 You can close a server that's running in a task using
 @schedule Base.throwto(listentask, InterruptException())
 =#
litas_oldtype = @schedule run(server_def_oldtype, PORT_OLDTYPE)

info("Chat server listening on $PORT_OLDTYPE")

#=

Now open another port using HTTP instead of HttpServer
We'll start by defining the input functions for HTTP's listen method

=#


function gatekeeper_newtype(reqheadersdict, ws)
    global lastreqheadersdict
    lastreqheadersdict = reqheadersdict
    global lastwsHTTP
    lastwsHTTP = ws
    # Inspect header Sec-WebSocket-Protocol to pick the right function. 
    wsfunc(ws)
end

httpfunc_newtype(req::HTTP.Request) = readstring(Pkg.dir("WebSockets","examples","chat_explore.html")) |> HTTP.Response

function server_def_newtype(http)
    global lasthttp
    lasthttp = http
    if WebSockets.is_upgrade(http.message)
        WebSockets.upgrade(gatekeeper_newtype, http)
    else
        HTTP.Servers.handle_request(httpfunc_newtype, http)
    end
end

info("Start HTTP server on port $(HTTPPORT)")
litas_newtype = @schedule HTTP.listen(server_def_newtype, "127.0.0.1", UInt16(HTTPPORT))

"""
This stops the servers using InterruptExceptions.
""" 
function closefromoutside()
   # Throwing exceptions can be slow. This function also 
   # starts a task which seems to not exit and free up 
   # its memory properly. HTTP.listen offers an alternative
   # method. See HTTP.listen > tcpref
    if isdefined(:litas_newtype)
        @schedule Base.throwto(litas_newtype, InterruptException())
    end
    if isdefined(:litas_oldtype)
        try
            @schedule Base.throwto(litas_oldtype, InterruptException())
        catch e
            info("closefromoutside: ", e)
        end
    end
end


nothing