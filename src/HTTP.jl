import HTTP:Response,   # For upgrade
            Request,    # For upgrade, target, origin, subprotocol
            Header,     # benchmarks, client_test, handshaketest
            header,     # For upgrade, subprotocol
            hasheader,  # For upgrade and check_upggrade
            setheader,  # For upgrade
            setstatus,  # For upgrade
            startwrite, # For upgrade
            startread,  # For _openstream
            handle,     # For _servercoroutine
            Connection, # For handshaketest
            Transaction,# For handshaketest
            URI,        # For open
            Handler,    # For WebSocketHandler, ServerWS, error_test
            RequestHandlerFunction,         # For ServerWS
            StatusError,                    # For open
            Servers,                        # For further imports
            Streams,                        # For further imports
            ConnectionPool                  # For further imports
import HTTP.ConnectionPool:
            getrawstream                    # For _openstream
import HTTP.Streams:
            Stream                          # For is_upgrade, handshaketest
import HTTP.Servers: MbedTLS                # For further imports
import HTTP.Servers.MbedTLS:
            SSLConfig                       # For ServerWS

"""
default_options() can be overruled by passing keyword arguments to the
ServerWS constructor.
# Options include
```
    sslconfig::Union{SSLConfig, Nothing}
    tcpisvalid::Function
    reuseaddr::Bool
    connection_count::Ref{Int}
    rate_limit::Union{Rational{Int}, Nothing}
    reuse_limit::Int
    readtimeout::Int
```
"""
default_options() = (in = Channel(1),
                    out = Channel(2),
                    sslconfig = nothing,
                    tcpisvalid = tcp->true,
                    reuseaddr = false,
                    connection_count = Ref(0),
                    rate_limit = nothing,
                    reuse_limit = typemax(Int),
                    readtimeout = 0)

"""
Initiate a websocket|client connection to server defined by url. If the server accepts
the connection and the upgrade to websocket, f is called with an open websocket|client

e.g. say hello, close and leave
```julia
using WebSockets
WebSockets.open("ws://127.0.0.1:8000") do ws
    write(ws, "Hello")
end;
```
If a server is listening and accepts, "Hello" is sent (as a CodeUnits{UInt8,String}).

On exit, a closing handshake is started. If the server is not currently reading
(which is a blocking function and it may be busy with other things), this side
will reset the underlying connection (ECONNRESET) after 10 seconds, and continue
execution without error.


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
    uri = URI(url)
    if uri.scheme != "ws" && uri.scheme != "wss"
        throw(ArgumentError(" bad argument url: Scheme not ws or wss. Input scheme: $(uri.scheme)"))
    end
    openstream(stream) = _openstream(f, stream, key)
    try
        HTTP.open(
            openstream,
            "GET", uri, headers;
            reuse_limit=0, verbose=verbose ? 2 : 0, kw...)
    catch err
        if typeof(err) <: HTTP.IOExtras.IOError
            throw(WebSocketClosedError(" while open ws|client: $(string(err.e.msg))"))
        elseif typeof(err) <: HTTP.StatusError
            return err.response
        else
           rethrow(err)
        end
    end
end

"Called by open with a stream connected to a server, after handshake is initiated"
function _openstream(f::Function, stream, key::String)
    startread(stream)
    response = stream.message
    if response.status != 101
        return
    end
    check_upgrade(stream)
    if header(response, "Sec-WebSocket-Accept") != generate_websocket_key(key)
        throw(WebSocketError(0, "Invalid Sec-WebSocket-Accept\n" *
                                "$response"))
    end
    # unwrap the stream
    io = getrawstream(stream)
    ws = WebSocket(io, false)
    try
        f(ws)
    finally
        close(ws)
    end
end

"""
Not called from user code in most cases.

Called by serve > _servercoroutine, or in you own server coroutine definition if
    `serve(ServerWS,  host, port, verbose)`
does not suit your purpose. Call 'upgrade' if is_upgrade(stream.message) returns true.

Responds to a WebSocket handshake request.
If the connection is acceptable, sends status code 101
and headers according to RFC 6455, then calls
user's handler function f with the connection wrapped in
a WebSocket instance.

f(ws)           is called with the websocket and no client info
f(headers, ws)  also receives a dictionary of request headers for added security measures

On exit from f, a closing handshake is started. If the client is not currently reading
(which is a blocking function), this side will reset the underlying connection (ECONNRESET)
after 10 seconds and continue execution.

If the upgrade is not accepted, responds to client with '400'.

See /examples/server_listen_syntax.jl
```
"""
function upgrade(f::Function, stream)
    check_upgrade(stream)
    if !hasheader(stream, "Sec-WebSocket-Version", "13")
                    setheader(stream, "Sec-WebSocket-Version" => "13")
                    setstatus(stream, 400)
                    startwrite(stream)
        return
    end
    if hasheader(stream, "Sec-WebSocket-Protocol")
        requestedprotocol = header(stream, "Sec-WebSocket-Protocol")
        if !hasprotocol(requestedprotocol)
            setheader(stream, "Sec-WebSocket-Protocol" => requestedprotocol)
            setstatus(stream, 400)
            startwrite(stream)
            return
        else
            setheader(stream, "Sec-WebSocket-Protocol" => requestedprotocol)
        end
    end
    key = header(stream, "Sec-WebSocket-Key")
    decoded = UInt8[]
    try
        decoded = base64decode(key)
    catch
        setstatus(stream, 400)
        startwrite(stream)
        return
    end
    if length(decoded) != 16 # Key must be 16 bytes
        setstatus(stream, 400)
        startwrite(stream)
        return
    end
    # This upgrade is acceptable. Send the response.
    setheader(stream, "Sec-WebSocket-Accept" => generate_websocket_key(key))
    setheader(stream, "Upgrade" => "websocket")
    setheader(stream, "Connection" => "Upgrade")
    setstatus(stream, 101)
    startwrite(stream)
    # Pass the connection on as a WebSocket.
    io = getrawstream(stream)
    ws = WebSocket(io, true)
    # If the callback function f has two methods,
    # prefer the more secure one which takes (request, websocket)
    try
        if applicable(f, stream.message, ws)
            f(stream.message, ws)
        else
            f(ws)
        end
    catch err
        # Some errors will not reliably propagate when rethrown,
        # especially compile time errors.
        # On the server side, this function is running in a new task for every connection made
        # from outside. The rethrown errors might get lost or caught elsewhere, so we also
        # duplicate them to stderr here.
        # For working examples of error catching and reading them on the .out channel, see 'error_test.jl'.
        # If for some reason, the error messages from your 'f' cannot be read properly, here are
        # three alternative ways of finding them so you can correct:
        # 1) Include try..catch in your 'f', and print the errors to stderr.
        # 2) Turn the connection direction around, i.e. try to
        # provoke the error on the client side.
        # 3) Connect through a browser if that is not already what you are doing.
        # Some error messages may currently be shown there.
        # 4) use keyword argument loglevel = 3.
        # 5) modify the global logger to take control.
#        @warn("WebSockets.upgrade: Caught unhandled error while calling argument function f, the handler / gatekeeper:\n\t")
#        mt = typeof(f).name.mt
#        fnam = splitdir(string(mt.defs.func.file))[2]
#        printstyled(stderr, color= :yellow,"f = ", string(f) * " at " * fnam * ":" * string(mt.defs.func.line) * "\nERROR:\t")
#        showerror(stderr, err, stacktrace(catch_backtrace()))
         rethrow(err)
    finally
        close(ws)
    end
end

"""
Not normally called from user code.
Throws WebSocketError if the upgrade message is not basically valid.
Called from 'upgrade' for potential server side websockets,
and from `_openstream' for potential client side websockets.
"""
function check_upgrade(r)
    if !hasheader(r, "Upgrade", "websocket")
        throw(WebSocketError(0, "Check upgrade: Expected \"Upgrade => websocket\"!\n$(r)"))
    end
    if !(hasheader(r, "Connection", "upgrade") || hasheader(r, "Connection", "keep-alive, upgrade"))
        throw(WebSocketError(0, "Check upgrade: Expected \"Connection => upgrade or Connection => keep alive, upgrade\"!\n$(r)"))
    end
end

"""
Not normally called from user code.
Fast checking for websocket upgrade request vs content requests.
Called on all new connections in '_servercoroutine'.
"""
function is_upgrade(r::Request)
    if (r isa Request && r.method == "GET")  || (r isa Response && r.status == 101)
        if header(r, "Connection", "") != "keep-alive"
            # "Connection => upgrade" for most and "Connection => keep-alive, upgrade" for Firefox.
            if hasheader(r, "Connection", "upgrade") || hasheader(r, "Connection", "keep-alive, upgrade")
                if lowercase(header(r, "Upgrade", "")) == "websocket"
                    return true
                end
            end
        end
    end
    return false
end

is_upgrade(stream::Stream) = is_upgrade(stream.message)

# Inline docs in 'WebSockets.jl'
target(req::Request) = req.target
subprotocol(req::Request) = header(req, "Sec-WebSocket-Protocol")
origin(req::Request) = header(req, "Origin")

"""
WSHandlerFunction(f::Function) <: Handler
 The provided argument should be one of the forms

    `f(WebSocket) => nothing`
    `f(Request, WebSocket) => nothing`

    The latter form is intended for gatekeeping, ref. RFC 6455 section 10.1
 f accepts a `WebSocket` and does interesting things with it, like reading, writing and exiting when finished
 and ready for starting the close handshake.
"""
struct WSHandlerFunction{F <: Function} <: Handler
    func::F # func(ws) or func(request, ws)
end


"""
    WebSockets.ServerWS(handler::Function, wshandler::Function, logger::IO)

WebSockets.ServerWS is an argument type for WebSockets.serve. Instances
include .in  and .out channels, see WebSockets.serve.

Special server options can be set using keyword arguments, and will overrule default_options().
"""
struct ServerWS
    handler::RequestHandlerFunction
    wshandler::WSHandlerFunction
    in::Channel{Any}
    out::Channel{Any}
    # the remaining parameters are server options,
    # documented in HTTP.jl
    sslconfig::Union{SSLConfig, Nothing}
    tcpisvalid::Function
    reuseaddr::Bool
    connection_count::Ref{Int}
    rate_limit::Union{Rational{Int}, Nothing}
    reuse_limit::Int
    readtimeout::Int
    # keywords only constructor
    ServerWS(;handler, wshandler, in, out, sslconfig, tcpisvalid, reuseaddr, connection_count, rate_limit, reuse_limit, readtimeout)=
          new(handler, wshandler, in, out, sslconfig, tcpisvalid, reuseaddr, connection_count, rate_limit, reuse_limit, readtimeout)
end
# User supplied keywords take precedence over default_options() here:
function ServerWS(handler::RequestHandlerFunction, wshandler::WSHandlerFunction; kwargs...)
    ServerWS(;handler = handler, wshandler = wshandler,  merge(default_options(), collect(kwargs))...)
end
# User supplied handler functions are packed into specialized types here.
# It also defines the most useful method ServerWS(h::Function,w::Function)
function ServerWS(h::Function, w::Function; kwargs...)
    ServerWS(RequestHandlerFunction(h), WSHandlerFunction(w); kwargs...)
end

to_ipaddr(ip::IPAddr) = ip
to_ipaddr(s::AbstractString) = parse(IPAddr, s)

"""
    WebSockets.serve(server::ServerWS, port)
    WebSockets.serve(server::ServerWS, host, port)
    WebSockets.serve(server::ServerWS, host, port, verbose)

A higher level interface for WebSockets.HTTP.listen.
If you are running serve asyncronously, the serve task will
exit when you close(ServerWS).

Puts any caught error and stacktrace on the server.out channel.
The server.in channel is used by close(ServerWS).

# Example
```julia
    @async WebSockets.serve(myserver_WS, "127.0.0.1", 8080)
```
After a suspected connection task failure:
```julia
    if isready(myserver_WS.out)
        stack_trace = take!(myserver_WS.out)
    end
```
"""
function serve(serverws::ServerWS, host, port, verbose)
    # An internal reference used for closing.
    tcpserver = Ref{Union{IOServer, Nothing}}(Sockets.listen(InetAddr(to_ipaddr(host), port)))
    # Start a couroutine that sleeps until something is put on the .in channel.
    @async begin
         # Next line will hold until something is put on the channel
         take!(serverws.in)
         if tcpserver[] != nothing
             close(tcpserver[])
             tcpserver[] = nothing
               GC.gc()
             yield()
        end
    end
    # We capture some variables in this inner function, which takes just one-argument.
    # The inner function will be called in a new task for every incoming connection.
    function _servercoroutine(stream::Stream)
        try
            if is_upgrade(stream.message)
                upgrade(serverws.wshandler.func, stream)
            else
                handle(serverws.handler, stream)
            end
        catch err
            put!(serverws.out, err)
            put!(serverws.out, stacktrace(catch_backtrace()))
        end
    end
    #
    # Call the constructor for the listen loop. When somebody tries to open a connection,
    # the listenloop
    # 1) Checks if we are willing to accept
    # 2) Spawns a new task, namely our coroutine _servercoroutine.
    HTTP.listen(_servercoroutine,
            host, port,
            verbose = verbose,
            sslconfig = serverws.sslconfig,
            tcpisvalid = serverws.tcpisvalid,
            server = tcpserver[],
            reuseaddr = serverws.reuseaddr,
            connection_count = serverws.connection_count,
            rate_limit = serverws.rate_limit,
            reuse_limit = serverws.reuse_limit,
            readtimeout = serverws.readtimeout)
    # We will only get to this point if the server is closed.
    # If this serve function is running as a coroutine, the server is closed
    # through the server.in channel, see above.
    return
end
serve(serverws::ServerWS; host= "127.0.0.1", port= "") =  serve(serverws, host, port, false)
serve(serverws::ServerWS, host, port) =  serve(serverws, host, port, false)
serve(serverws::ServerWS, port) =  serve(serverws, "127.0.0.1", port, false)


function Base.close(serverws::ServerWS)
    put!(serverws.in, "Close!")
    if isready(serverws.out)
        @warn "Server closed. Error messages exist on the server's .out channel. Check
            string(take!(yourserverWS.out))"
    end
    return
end
