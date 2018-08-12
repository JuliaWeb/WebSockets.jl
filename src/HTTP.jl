"""
Initiate a websocket|client connection to server defined by url. If the server accepts
the connection and the upgrade to websocket, f is called with an open websocket|client

e.g. say hello, close and leave
```julia
using WebSockets
WebSockets.open("ws://127.0.0.1:8000") do ws
    write(ws, "Hello")
    println("that's it")
end;
```
If a server is listening and accepts, "Hello" is sent (as a Vector{UInt8}).

On exit, a closing handshake is started. If the server is not currently reading
(which is a blocking function), this side will reset the underlying connection (ECONNRESET)
after a reasonable amount of time and continue execution.
"""
function open(f::Function, url; verbose=false, subprotocol = "", kw...)
    key = base64encode(rand(UInt8, 16))
    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => key,
        "Sec-WebSocket-Version" => "13"
    ]
    if subprotocol != ""
        push!(headers, "Sec-WebSocket-Protocol" => subprotocol )
    end

    if in('#', url)
        throw(ArgumentError(" replace '#' with %23 in url: $url"))
    end

    uri = HTTP.URIs.URI(url)
    if uri.scheme != "ws" && uri.scheme != "wss"
        throw(ArgumentError(" bad argument url: Scheme not ws or wss. Input scheme: $(uri.scheme)"))
    end

    try
        HTTP.open("GET", uri, headers;
                reuse_limit=0, verbose=verbose ? 2 : 0, kw...) do http
                    _openstream(f, http, key)
                end
    catch err
        if typeof(err) <: Base.IOError
            throw(WebSocketClosedError(" while open ws|client: $(string(err))"))
        elseif typeof(err) <: HTTP.ExceptionRequest.StatusError
            return err.response
        else
           rethrow(err)
        end
    end
end
"Called by open with a stream connected to a server, after handshake is initiated"
function _openstream(f::Function, http::HTTP.Streams.Stream, key::String)

    HTTP.startread(http)

    status = http.message.status
    if status != 101
        return
    end

    check_upgrade(http)

    if HTTP.header(http, "Sec-WebSocket-Accept") != generate_websocket_key(key)
        throw(WebSocketError(0, "Invalid Sec-WebSocket-Accept\n" *
                                "$(http.message)"))
    end

    io = HTTP.ConnectionPool.getrawstream(http)
    ws = WebSocket(io,false)
    try
        f(ws)
    finally
        close(ws)
    end

end


"""
Used as part of a server definition. Call this if
is_upgrade(http.message) returns true.

Responds to a WebSocket handshake request.
If the connection is acceptable, sends status code 101
and headers according to RFC 6455, then calls
user's handler function f with the connection wrapped in
a WebSocket instance.

f(ws)           is called with the websocket and no client info
f(headers, ws)  also receives a dictionary of request headers for added security measures

On exit from f, a closing handshake is started. If the client is not currently reading
(which is a blocking function), this side will reset the underlying connection (ECONNRESET)
after a reasonable amount of time and continue execution.

If the upgrade is not accepted, responds to client with '400'.


e.g. server with local error handling. Combine with WebSocket.open example.
```julia
import HTTP
using WebSockets

badgatekeeper(reqdict, ws) = sqrt(-2)
handlerequest(req) = HTTP.Response(501)

try
    HTTP.listen("127.0.0.1", UInt16(8000)) do http
        if WebSockets.is_upgrade(http.message)
            WebSockets.upgrade(badgatekeeper, http)
        else
            HTTP.Servers.handle_request(handlerequest, http)
        end
    end
catch err
    showerror(stderr, err)
    println.(stacktrace(catch_backtrace())[1:4])
end
```
"""
function upgrade(f::Function, http::HTTP.Stream)
    # Double check the request. is_upgrade should already have been called by user.
    check_upgrade(http)
    if !HTTP.hasheader(http, "Sec-WebSocket-Version", "13")
        HTTP.setheader(http, "Sec-WebSocket-Version" => "13")
        HTTP.setstatus(http, 400)
        HTTP.startwrite(http)
        return
    end
    if HTTP.hasheader(http, "Sec-WebSocket-Protocol")
        requestedprotocol = HTTP.header(http, "Sec-WebSocket-Protocol")
        if !hasprotocol(requestedprotocol)
            HTTP.setheader(http, "Sec-WebSocket-Protocol" => requestedprotocol)
            HTTP.setstatus(http, 400)
            HTTP.startwrite(http)
            return
        else
            HTTP.setheader(http, "Sec-WebSocket-Protocol" => requestedprotocol)
        end
    end
    key = HTTP.header(http, "Sec-WebSocket-Key")
    decoded = UInt8[]
    try
        decoded = base64decode(key)
    catch
        HTTP.setstatus(http, 400)
        HTTP.startwrite(http)
        return
    end
    if length(decoded) != 16 # Key must be 16 bytes
        HTTP.setstatus(http, 400)
        HTTP.startwrite(http)
        return
    end
    # This upgrade is acceptable. Send the response.
    HTTP.setheader(http, "Sec-WebSocket-Accept" => generate_websocket_key(key))
    HTTP.setheader(http, "Upgrade" => "websocket")
    HTTP.setheader(http, "Connection" => "Upgrade")
    HTTP.setstatus(http, 101)
    HTTP.startwrite(http)
    # Pass the connection on as a WebSocket.
    io = HTTP.ConnectionPool.getrawstream(http)
    ws = WebSocket(io, true)
    # If the callback function f has two methods,
    # prefer the more secure one which takes (request, websocket)
    try
        if applicable(f, http.message, ws)
            f(http.message, ws)
        else
            f(ws)
        end
#    catch err
#        @warn("WebSockets.HTTP.upgrade: Caught unhandled error while calling argument function f, the handler / gatekeeper:\n\t")
#        mt = typeof(f).name.mt
#        fnam = splitdir(string(mt.defs.func.file))[2]
#        print_with_color(:yellow, STDERR, "f = ", string(f) * " at " * fnam * ":" * string(mt.defs.func.line) * "\nERROR:\t")
#        showerror(STDERR, err, stacktrace(catch_backtrace()))
    finally
        close(ws)
    end
end

"It is up to the user to call 'is_upgrade' on received messages.
This provides double checking from within the 'upgrade' function."
function check_upgrade(http)
    if !HTTP.hasheader(http, "Upgrade", "websocket")
        throw(WebSocketError(0, "Check upgrade: Expected \"Upgrade => websocket\"!\n$(http.message)"))
    end
    if !(HTTP.hasheader(http, "Connection", "upgrade") || HTTP.hasheader(http, "Connection", "keep-alive, upgrade"))
        throw(WebSocketError(0, "Check upgrade: Expected \"Connection => upgrade or Connection => keep alive, upgrade\"!\n$(http.message)"))
    end
end

"""
Fast checking for websockets vs http requests, performed on all new HTTP requests.
Similar to HttpServer.is_websocket_handshake
"""
function is_upgrade(r::HTTP.Message)
    if (r isa HTTP.Request && r.method == "GET")  || (r isa HTTP.Response && r.status == 101)
        if HTTP.header(r, "Connection", "") != "keep-alive"
            # "Connection => upgrade" for most and "Connection => keep-alive, upgrade" for Firefox.
            if HTTP.hasheader(r, "Connection", "upgrade") || HTTP.hasheader(r, "Connection", "keep-alive, upgrade")
                if lowercase(HTTP.header(r, "Upgrade", "")) == "websocket"
                    return true
                end
            end
        end
    end
    return false
end
# Inline docs in 'WebSockets.jl'
target(req::HTTP.Messages.Request) = req.target
subprotocol(req::HTTP.Messages.Request) = HTTP.header(req, "Sec-WebSocket-Protocol")
origin(req::HTTP.Messages.Request) = HTTP.header(req, "Origin")  

"""
WebsocketHandler(f::Function) <: HTTP.Handler

A simple Function-wrapper for HTTP.
The provided argument should be one of the forms
    `f(WebSocket) => nothing`
    `f(HTTP.Request, WebSocket) => nothing`
The latter form is intended for gatekeeping, ref. RFC 6455 section 10.1

f accepts a `WebSocket` and does interesting things with it, like reading, writing and exiting when finished.
"""
struct WebsocketHandler{F <: Function} <: HTTP.Handler
    func::F # func(ws) or func(request, ws)
end


"""
    WebSockets.ServerWS(::HTTP.HandlerFunction, ::WebSockets.WebsocketHandler)

WebSockets.ServerWS is an argument type for WebSockets.serve. Instances
include .in  and .out channels, see WebSockets.serve.
"""
mutable struct ServerWS{T <: HTTP.Servers.Scheme, H <: HTTP.Handler, W <: WebsocketHandler}
    handler::H
    wshandler::W
    logger::IO
    in::Channel{Any}
    out::Channel{Any}
    options::HTTP.ServerOptions

    ServerWS{T, H, W}(handler::H, wshandler::W, logger::IO = HTTP.compat_stdout(), ch=Channel(1), ch2=Channel(2),
                 options=HTTP.ServerOptions()) where {T, H, W} =
        new{T, H, W}(handler, wshandler, logger, ch, ch2, options)
end

ServerWS(h::Function, w::Function, l::IO=HTTP.compat_stdout();
            cert::String="", key::String="", args...) = ServerWS(HTTP.HandlerFunction(h), WebsocketHandler(w), l;
                                                         cert=cert, key=key, ratelimit = 1//0, args...)
function ServerWS(handler::H,
                wshandler::W,
                logger::IO = HTTP.compat_stdout();
                cert::String = "",
                key::String = "",
                args...) where {H <: HTTP.Handler, W <: WebsocketHandler}
    if cert != "" && key != ""
        serverws = ServerWS{HTTP.Servers.https, H, W}(handler, wshandler, logger, Channel(1), Channel(2), HTTP.ServerOptions(; sslconfig=HTTP.MbedTLS.SSLConfig(cert, key), args...))
    else
        serverws = ServerWS{HTTP.Servers.http, H, W}(handler, wshandler, logger, Channel(1), Channel(2), HTTP.ServerOptions(; args...))
    end
    return serverws
end
ratlimit = 1//0
"""
    WebSockets.serve(server::ServerWS, port)
    WebSockets.serve(server::ServerWS, host, port)
    WebSockets.serve(server::ServerWS, host, port, verbose)

A wrapper for HTTP.listen.
Puts any caught error and stacktrace on the server.out channel.
To stop a running server, put HTTP.Servers.KILL on the .in channel.
```julia
    @shedule WebSockets.serve(server, "127.0.0.1", 8080)
```
After a suspected connection task failure:
```julia
    if isready(myserver_WS.out)
        stack_trace = take!(myserver_WS.out)
    end
```
"""
function serve(server::ServerWS{T, H, W}, host, port, verbose) where {T, H, W}

    tcpserver = Ref{HTTP.Sockets.TCPServer}()

    @async begin
        while !isassigned(tcpserver)
            sleep(1)
        end
        while true
            val = take!(server.in)
            val == HTTP.Servers.KILL && close(tcpserver[])
        end
    end

    HTTP.listen(host, port;
           tcpref=tcpserver,
           ssl=(T == HTTP.Servers.https),
           sslconfig = server.options.sslconfig,
           verbose = verbose,
           tcpisvalid = server.options.ratelimit > 0 ? HTTP.Servers.check_rate_limit :
                                                     (tcp; kw...) -> true,
           ratelimits = Dict{IPAddr, HTTP.Servers.RateLimit}(),
           ratelimit = server.options.ratelimit) do stream::HTTP.Stream
                            try
                                if is_upgrade(stream.message)
                                    upgrade(server.wshandler.func, stream)
                                else
                                    HTTP.Servers.handle_request(server.handler.func, stream)
                                end
                            catch err
                                put!(server.out, err)
                                put!(server.out, stacktrace(catch_backtrace()))
                            end
            end
    return
end
serve(server::WebSockets.ServerWS, host, port) =  serve(server, host, port, false)
serve(server::WebSockets.ServerWS, port) =  serve(server, "127.0.0.1", port, false)