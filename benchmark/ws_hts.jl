# Submodule Julia HTTP Server
# HTTP and WebSockets need to be loaded in the calling context.
# LOAD_PATH must include logutils
# Intended for accepting echoing clients, such as ws_jce.jl, and
# running echo tests with that client.
# The server stays open until close_hts or the websocket is closed.
module ws_hts
using ..WebSockets
using ..WebSockets.HTTP
import ..WebSockets.Header

# We want to log to a separate file, so
# we use our own instance of logutils_ws here.
import logutils_ws: logto, clog, zlog, zflush, clog_notime
const SRCPATH = Base.source_dir() == nothing ? Pkg.dir("WebSockets", "benchmark") : Base.source_dir()
const SERVEFILE = "bce.html"
const PORT = 8000
const SERVER = "127.0.0.1"
const WSMAXTIME = Base.Dates.Second(600)
const WEBSOCKET = Vector{WebSockets.WebSocket}()
const TCPREF = Ref{Base.IOServer}()
"Run asyncronously or in separate process"
function listen_hts()
    id = "listen_hts"
    try
        clog(id,"listen_hts starts on ", SERVER, ":", PORT)
        zflush()
        HTTP.listen(SERVER, UInt16(PORT), tcpref = TCPREF) do http
            if WebSockets.is_upgrade(http.message)
                acceptholdws(http)
                clog(id, "Websocket closed, server stays open until ws_hts.close_hts()")
            else
                WebSockets.handle_request(handlerequest, http)
            end
        end
    catch err
        clog(id, :red, err)
        clog_notime.(stacktrace(catch_backtrace())[1:4])
        zflush()
    end
end

"Accepts an incoming connection, upgrades to websocket,
and waits for timeout or a closed socket.
Also stops the server from accepting more connections on exit."
function acceptholdws(http)
    id = "ws_hts.acceptholdws"
    zlog(id);zflush()
    # If the ugrade is successful, just hold the reference and thread
    # of execution. Other tasks may do useful things with it.
    WebSockets.upgrade(http) do ws
        if length(WEBSOCKET) > 0
            # unexpected behaviour.
            if !isopen(WEBSOCKET[1])
                pop!(WEBSOCKET)
            else
                msg = " A websocket is already open. Not accepting the attempt at opening more."
                clog(id, :red, msg);zflush()
                return
            end
        end
        push!(WEBSOCKET, ws)
        zlog(id, ws);zflush()
        t1 = now() + WSMAXTIME
        while isopen(ws) && now() < t1
            yield()
        end
        length(WEBSOCKET) > 0 && pop!(WEBSOCKET)
        zlog(id, " exiting");zflush()
    end
end
"Returns a websocket or a string"
function getws_hts()
    id = "getws_hts"
    if length(WEBSOCKET) > 0
        if isopen(WEBSOCKET[1])
            zlog(id, " return reference")
            return WEBSOCKET[1]
        else
            msg = " Websocket is referred but not open. Acceptholdws might not have been scheduled after is was closed."
            clog(id, msg)
            zflush()
            return msg
        end
    else
        if !isdefined(TCPREF, :x)
            msg = " No server running yet, run ws_hts.listen_hts() or wait"
        else
            msg = " No websocket has connected yet, run ws_hce.echowithdelay_jce() or wait"
        end
        zlog(id, msg)
        return id * msg
    end
end




"HTTP request -> HTTP response."
function handlerequest(request::HTTP.Request)
    id = "handlerequest"
    zlog(id, request)
    response = responseskeleton(request)
    try
        if request.method == "GET"
            response = resp_HTTP(request.target, response)
        elseif request.method == "HEAD"
            response = resp_HTTP(request.target, response)
            response.body = Array{UInt8,1}()
        else
            response = HTTP.Response(501, "Not implemented method: $(request.method), fix $id")
        end
    catch
    end
    zlog(id, response)
    response
end


"""
Tell browser about the methods this server supports.
"""
function responseskeleton(request::HTTP.Request)
    r = HTTP.Response()
    HTTP.Messages.appendheader(r, Header("Allow" => "GET,HEAD"))
    HTTP.Messages.appendheader(r, Header("Connection" => "close"))
    r #
end

"request.target -> HTTP.Response , building on a skeleton response"
function resp_HTTP(resource::String, resp::HTTP.Response)
    id = "resp_HTTP"
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

"Close the websocket, stop the server. TODO improve"
function close_hts()
    clog("ws_hts.close_hts")
    length(WEBSOCKET) >0 && isopen(WEBSOCKET[1]) && close(WEBSOCKET[1]) && sleep(0.5)
    isassigned(TCPREF) && close(TCPREF.x)
end

end # module
"""
For debugging:

import HTTP
using WebSockets
using Dates
const SRCPATH = Base.source_dir() == nothing ? Pkg.dir("WebSockets", "benchmark") :Base.source_dir()
const LOGGINGPATH = realpath(joinpath(SRCPATH, "../logutils/"))
# for finding local modules
SRCPATH ∉ LOAD_PATH && push!(LOAD_PATH, SRCPATH)
LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)
import ws_hts.listen_hts
tas = @async ws_hts.listen_hts()
sleep(7)
hts = ws_hts.getws_hts()
"""
