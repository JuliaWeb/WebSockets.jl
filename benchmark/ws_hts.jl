# Intended for running in a separate process, e.g. in a worker process.
# Intended for accepting echoing clients, such as ws_jce.jl, and
# running echo tests with that client.
#
# The websocket reference is held until close_hts, or the websocket is closed.
# LOAD_PATH must include logutils
# The server stays open until close_hts or the websocket is closed.
module ws_hts
if !@isdefined LOGGINGPATH
    (@__DIR__) ∉ LOAD_PATH && push!(LOAD_PATH, @__DIR__)
    const LOGGINGPATH = realpath(joinpath(@__DIR__, "..", "logutils"))
    LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)
end

using WebSockets
import WebSockets: Stream,
                Request
#=
import WebSockets.HTTP: Header,
             Sockets.TCPServer,
             listen,
             Servers.handle_request,
             Request,
             Response,
             Messages.appendheader,
             Stream
import WebSockets: WebSocket,
            origin,
            is_upgrade,
			upgrade
=#
using logutils_ws
using Dates
export listen_hts, getws_hts, close_hts
# For debugging, we include a handler for connecting with a browser.
# In case of some errors, HTTP will redirect error messages to
# the browser. Openn 127.0.0.1:8000 to check.
const SERVEFILE = "hts.html"
const SRCPATH = @__DIR__
const PORT = 8000
const SERVER = "127.0.0.1"
const WSMAXTIME = Second(600)
const WEBSOCKET = Vector{WebSockets.WebSocket}()
const TCPREF = Ref{Base.IOServer}()
const LOGFILE = string(@__MODULE__)

function __init__()
    global LOGSTREAM = open(joinpath((@__DIR__), "logs", LOGFILE), "w")
    global MODLOG = WebSocketLogger(LOGSTREAM)
    global_logger(MODLOG)
    nothing
end


"Run asyncronously or in separate process"
function listen_hts()
    id = "listen_hts "
    if !isopen(LOGSTREAM)
         open(LOGSTREAM, "w")
    end
    try
        @debug id, " starts on ", SERVER, ":", PORT
        flush(LOGSTREAM)
        listen(SERVER, UInt16(PORT), tcpref = TCPREF) do stream::Stream
            @debug id, "received request, argument of type ", :bold, typeof(stream)
            while !eof(stream)
                readavailable(stream)
            end
            if is_upgrade(stream.message)
                @debug(id, "That is an upgrade!")
                acceptholdws(stream)
                @debug id, "Websocket closed"
                setstatus(stream, 200)
            else
                WebSockets.handle_request(handlerequest, http)
            end
        end
    catch err
        @error id, :red, "Error", logutils_ws.logbody_s.(stacktrace(catch_backtrace())[1:4]...)
        flush(LOGSTREAM)
    finally
        close(LOGSTREAM)
    end
end

"Accepts an incoming connection, upgrades to websocket,
and waits for timeout or a closed socket.
Also stops the server from accepting more connections on exit."
function acceptholdws(stream)
    id = "ws_hts.acceptholdws"
    @info(id);flush(LOGSTREAM)
    # If the ugrade is successful, just hold the reference and thread
    # of execution. Other tasks may do useful things with it.
    upgrade(stream) do ws
        if length(WEBSOCKET) > 0
            # unexpected behaviour.
            if !isopen(WEBSOCKET[1])
                pop!(WEBSOCKET)
            else
                msg = " A websocket is already open. Not accepting the attempt at opening more."
                @debug (id, :red, msg);flush(LOGSTREAM)
                return
            end
        end
        push!(WEBSOCKET, ws)
        @info(id, ws);flush(LOGSTREAM)
        t1 = now() + WSMAXTIME
        while isopen(ws) && now() < t1
            yield()
        end
        length(WEBSOCKET) > 0 && pop!(WEBSOCKET)
        @info(id, " exiting")
        flush(LOGSTREAM)
    end
end
"Returns a websocket or a string"
function getws_hts()
    id = "getws_hts"
    if length(WEBSOCKET) > 0
        if isopen(WEBSOCKET[1])
            @info(id, " return reference")
            return WEBSOCKET[1]
        else
            msg = " Websocket is referred but not open. Acceptholdws might not have been scheduled after is was closed."
            @debug (id, msg)
            flush(LOGSTREAM)
            return msg
        end
    else
        if !isdefined(TCPREF, :x)
            msg = " No server running yet, run ws_hts.listen_hts() or wait"
        else
            msg = " No websocket has connected yet, run ws_hce.echowithdelay_jce() or wait"
        end
        @info(id, msg)
        flush(LOGSTREAM)
        return id * msg
    end
end

"HTTP request -> HTTP response."
function handle(request::Request)
    id = "handle "
    @info(id, "The type of request is", typeof(request))
    try
        if request.method == "GET"
            response = resp_HTTP(request.target)
        else
            response = Response(501, "Not implemented method: $(request.method), fix $id")
        end
    catch err
        @error id, :red, "Error", logutils_ws.logbody_s.(stacktrace(catch_backtrace())[1:4]...)
    end
    @info(id, response)
    @info(id, "The type of response is ", typeof(response))
    response
end

"request.target string -> HTTP.Response"
function resp_HTTP(resource::String)
    id = "resp_HTTP"
    @info(id, "Well, we got the request for resource ", resource)
    r = Response()
    appendheader(r, Header("Allow" => "GET"))
    appendheader(r, Header("Connection" => "close"))
    if resource == "/favicon.ico"
        s = read(joinpath(SRCPATH, "favicon.ico"))
        push!(resp.headers, "Content-Type" => "image/x-icon")
    else
        s = read(joinpath(SRCPATH, SERVEFILE))
        push!(resp.headers, "Content-Type" => "text/html")
    end
    resp.body = s
    push!(resp.headers, "Content-Length" => string(length(s)))
    resp.status = 200
    resp
end

"Close the websocket, stop the server and close logstream."
function close_hts()
    if length(WEBSOCKET) > 0 && isopen(WEBSOCKET[1])
        @debug "close_hts: Start close websocket"
        # Note, if the client end is not actively reading, this will
        # wait for, by default, 10 seconds.
        close(WEBSOCKET[1])
    else
        if isassigned(TCPREF)
            @debug "Start close_hts"
            close(TCPREF.x)
        end
    end
    @debug "Close logstream"
end

end # module
#=
For debugging in a separate console:

using WebSockets
wspath = realpath(joinpath(WebSockets |> pathof |> dirname, ".."))
include(joinpath(wspath, "benchmark", "ws_hts.jl"))
include(joinpath(wspath, "logutils", "logutils_ws.jl"))
using ws_hts
listen_hts()
tas = @async listen_hts()
sleep(7)
hts = ws_hts.getws_hts()
=#
