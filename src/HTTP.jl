import HTTP
import HTTP.Servers: MbedTLS

"Called by open with a stream connected to a server, after handshake is initiated"
function _openstream(f::Function, stream, key::String)
    println("Try startread")
    HTTP.startread(stream)
    println("Finished startread")
    response = stream.message
    if response.status != 101
        return
    end
    check_upgrade(stream)
    if HTTP.header(response, "Sec-WebSocket-Accept") != generate_websocket_key(key)
        throw(WebSocketError(0, "Invalid Sec-WebSocket-Accept\n" *
                                "$response"))
    end
    # unwrap the stream
    io = HTTP.ConnectionPool.getrawstream(stream)
    ws = WebSocket(io, false)
    try
        f(ws)
    finally
        close(ws)
    end
end

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
    uri = HTTP.URI(url)
    if uri.scheme != "ws" && uri.scheme != "wss"
        throw(ArgumentError(" bad argument url: Scheme not ws or wss. Input scheme: $(uri.scheme)"))
    end
    openstream(stream) = _openstream(f, stream, key)
    try
        println("*******************************************************************")
        println(HTTP.stack(reuse_limit=0,verbose=verbose ? 2 : 0))
        println("*******************************************************************")
        HTTP.open(openstream,
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



"""
Used as part of a server definition. Call this if
is_upgrade(stream.message) returns true.

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
using WebSockets

badgatekeeper(reqdict, ws) = sqrt(-2)
handlerequest(req) = WebSockets.Response(501)
const SERVERREF = Ref{Base.IOServer}()
try
    WebSockets.HTTP.listen("127.0.0.1", UInt16(8000), tcpref = SERVERREF) do stream
        if WebSockets.is_upgrade(stream.message)
            WebSockets.upgrade(badgatekeeper, stream)
        else
            WebSockets.handle_request(handlerequest, stream)
        end
    end
catch err
    showerror(stderr, err)
    println.(stacktrace(catch_backtrace())[1:4])
end
```
"""
function upgrade(f::Function, stream)
    check_upgrade(stream)
    if !HTTP.hasheader(stream, "Sec-WebSocket-Version", "13")
        HTTP.setheader(stream, "Sec-WebSocket-Version" => "13")
        HTTP.setstatus(stream, 400)
        HTTP.startwrite(stream)
        return
    end
    if HTTP.hasheader(stream, "Sec-WebSocket-Protocol")
        requestedprotocol = HTTP.header(stream, "Sec-WebSocket-Protocol")
        if !hasprotocol(requestedprotocol)
            HTTP.setheader(stream, "Sec-WebSocket-Protocol" => requestedprotocol)
            HTTP.setstatus(stream, 400)
            HTTP.startwrite(stream)
            return
        else
            HTTP.setheader(stream, "Sec-WebSocket-Protocol" => requestedprotocol)
        end
    end
    key = HTTP.header(stream, "Sec-WebSocket-Key")
    decoded = UInt8[]
    try
        decoded = base64decode(key)
    catch
        HTTP.setstatus(stream, 400)
        HTTP.startwrite(stream)
        return
    end
    if length(decoded) != 16 # Key must be 16 bytes
        HTTP.setstatus(stream, 400)
        HTTP.startwrite(stream)
        return
    end
    # This upgrade is acceptable. Send the response.
    HTTP.setheader(stream, "Sec-WebSocket-Accept" => generate_websocket_key(key))
    HTTP.setheader(stream, "Upgrade" => "websocket")
    HTTP.setheader(stream, "Connection" => "Upgrade")
    HTTP.setstatus(stream, 101)
    HTTP.startwrite(stream)
    # Pass the connection on as a WebSocket.
    io = HTTP.ConnectionPool.getrawstream(stream)
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
Throws WebSocketError if the upgrade message is not basically valid.
Called from 'upgrade' for potential server side websockets,
and from `_openstream' for potential client side websockets.
Not normally called from user code.
"""
function check_upgrade(r)
    if !HTTP.hasheader(r, "Upgrade", "websocket")
        throw(WebSocketError(0, "Check upgrade: Expected \"Upgrade => websocket\"!\n$(r)"))
    end
    if !(HTTP.hasheader(r, "Connection", "upgrade") || HTTP.hasheader(r, "Connection", "keep-alive, upgrade"))
        throw(WebSocketError(0, "Check upgrade: Expected \"Connection => upgrade or Connection => keep alive, upgrade\"!\n$(r)"))
    end
end

"""
Fast checking for websocket upgrade request vs content requests.
Called on all new connections in '_servercoroutine'.
"""
function is_upgrade(r::HTTP.Request)
    if (r isa Request && r.method == "GET")  || (r isa Response && r.status == 101)
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

is_upgrade(stream::HTTP.Stream) = is_upgrade(stream.message)

# Inline docs in 'WebSockets.jl'
target(req::HTTP.Request) = req.target
subprotocol(req::HTTP.Request) = HTTP.header(req, "Sec-WebSocket-Protocol")
origin(req::HTTP.Request) = HTTP.header(req, "Origin")

struct ServerOptions
    sslconfig::Union{HTTP.Servers.MbedTLS.SSLConfig, Nothing}
    readtimeout::Float64
    ratelimit::Rational{Int}
    support100continue::Bool
    chunksize::Union{Nothing, Int}
    logbody::Bool
end
function ServerOptions(;
        sslconfig::Union{HTTP.Servers.MbedTLS.SSLConfig, Nothing} = nothing,
        readtimeout::Float64=180.0,
        ratelimit::Rational{Int}= 10 // 1,
        support100continue::Bool=true,
        chunksize::Union{Nothing, Int}=nothing,
        logbody::Bool=true
    )
    ServerOptions(sslconfig, readtimeout, ratelimit, support100continue, chunksize, logbody)
end
"""
    WebSockets.ServerWS(handler::Function, wshandler::Function, logger::IO)

WebSockets.ServerWS is an argument type for WebSockets.serve. Instances
include .in  and .out channels, see WebSockets.serve.

Server options can be set using keyword arguments, see methods(WebSockets.ServerWS)
"""
mutable struct ServerWS{S <: Val, H <: HTTP.RequestHandlerFunction, W <: HTTP.StreamHandlerFunction}
    handler::H
    wshandler::W
    logger::IO
    in::Channel{Any}
    out::Channel{Any}
    options::ServerOptions

    ServerWS{S, H, W}(handler::H, wshandler::W, logger::IO = stdout, ch=Channel(1), ch2=Channel(2),
                 options = ServerOptions()) where {S, H, W} =
        new{S, H, W}(handler, wshandler, logger, ch, ch2, options)
end

# Define ServerWS without wrapping the functions first. Rely on argument sequence.
function ServerWS(h::Function, w::Function, l::IO=stdout;
            cert::String="", key::String="", args...)

        ServerWS(HTTP.RequestHandlerFunction(h),
                HTTP.StreamHandlerFunction(w), l;
                cert=cert, key=key, ratelimit = 10//1, args...)
end
# Define ServerWS with keyword arguments only
function ServerWS(;handler::Function, wshandler::Function,
            logger::IO=stdout,
            cert::String="", key::String="", args...)

        ServerWS(HTTP.RequestHandlerFunction(handler),
                HTTP.StreamHandlerFunction(wshandler), logger;
                cert=cert, key=key, ratelimit = 10//1, args...)
end

# Define ServerWS with function wrappers
function ServerWS(handler::H,
                wshandler::W,
                logger::IO = stdout;
                cert::String = "",
                key::String = "",
                ratelimit = 10//1,
                args...) where {H <: HTTP.RequestHandlerFunction, W <: HTTP.StreamHandlerFunction}

    sslconfig = nothing;
    S = typeof(HTTP.Handlers.SCHEMES["http"]) # http is an imported DataType
    if cert != "" && key != ""
        sslconfig = HTTP.Servers.MbedTLS.SSLConfig(cert, key)
        S = typeof(HTTP.Handlers.SCHEMES["https"]) # https is an imported DataType
    end
    serverws = ServerWS{S, H, W}(  handler,
                                        wshandler,
                                        logger, Channel(1), Channel(2),
                                        ServerOptions(;ratelimit = ratelimit,
                                                                     args...))
end
"""
    WebSockets.serve(server::ServerWS, port)
    WebSockets.serve(server::ServerWS, host, port)
    WebSockets.serve(server::ServerWS, host, port, verbose)

A wrapper for WebSockets.HTTP.listen.
Puts any caught error and stacktrace on the server.out channel.
To stop a running server, put a byte on the server.in channel.
```julia
    @async WebSockets.serve(server, "127.0.0.1", 8080)
```
After a suspected connection task failure:
```julia
    if isready(myserver_WS.out)
        stack_trace = take!(myserver_WS.out)
    end
```
"""
function serve(server::ServerWS{S, H, W}, host, port, verbose) where {S, H, W}
    println("server: $(server)")
    println("host: $(host)")
    println("port: $(port)")
    println("verbose: $(verbose)")
    println("server.in: $(server.in)")
    # An internal reference used for closing.
    tcpserver = Ref{Union{Base.IOServer, Nothing}}()
    # Start a couroutine that sleeps until tcpserver is assigned,
    # ie. the reference is established further down.server:
    # It then enters the while loop, where it
    # waits for put! to channel .in. The value does not matter.
    # The coroutine then closes the server and finishes its run.
    # Note that WebSockets v1.0.3 required the channel input to be HTTP.KILL,
    # but will now kill the server regardless of what is sent.
    # @async begin
    #     # Next line will hold
    #     take!(server.in)
    #     println("take! has completed")
    #     close(tcpserver[])
    #     tcpserver[] = nothing
    #     GC.gc()
    #     yield()
    # end
    # We capture some variables in this inner function, which takes just one-argument.
    # The inner function will be called in a new task for every incoming connection.
    function _servercoroutine(stream::HTTP.Stream)
        println("Try _servercoroutine")
        try
            if is_upgrade(stream.message)
                HTTP.handle(server.wshandler, stream)
            else
                HTTP.handle(server.handler, stream)
            end
        catch err
            put!(server.out, err)
            put!(server.out, stacktrace(catch_backtrace()))
        end
    end
    #
    # Call the listen loop, which
    # 1) Checks if we are ready to accept a new task yet. It does
    #    so using the function given as a keyword argument, tcpisvalid.
    #    The default tcpvalid function is defined in this module.
    # 2) If we are ready, it spawns a new task or coroutine _servercoroutine.
    #
    println("Scheme: $(S) $(S == Val{:https})")
    println("SSLConfig: $(isnothing(server.options.sslconfig) ? "Nothing" : server.options.sslconfig)")
    println("Server Options: $(server.options)")
    HTTP.listen(_servercoroutine,
            host, port;
            # server=tcpserver,
            # ssl=(S == Val{:https}),
            sslconfig = server.options.sslconfig,
            verbose = verbose,
            # tcpisvalid = server.options.ratelimit > 0 ? 
            #     tcp -> checkratelimit!(tcp,ratelimit=server.options.ratelimit) :
            #     tcp -> true,
            # ratelimits = Dict{IPAddr, HTTP.Servers.MbedTLS.SSLConfig}(),
            rate_limit = server.options.ratelimit)
    # We will only get to this point if the server is closed.
    # If this serve function is running as a coroutine, the server is closed
    # through the server.in channel, see above.
    return
end
serve(server::ServerWS; host= "127.0.0.1", port= "") =  serve(server, host, port, false)
serve(server::ServerWS, host, port) =  serve(server, host, port, false)
serve(server::ServerWS, port) =  serve(server, "127.0.0.1", port, false)

"""
'checkratelimit!' updates a dictionary of IP addresses which keeps track of their
connection quota per time window.

The allowed connections per time is given in keyword argument ratelimit.

The actual ratelimit::Rational value, is normally given as a field value in ServerOpions.

'checkratelimit!' is the default rate limiting function for ServerWS, which passes
it as the 'tcpisvalid' argument to 'WebSockets.HTTP.listen'. Other functions can be given as a
keyword argument, as long as they adhere to this form, which WebSockets.HTTP.listen
expects.
"""
checkratelimit!(tcp::Base.PipeEndpoint) = true
function checkratelimit!(tcp;
                          ratelimit::Rational{Int}=Int(10)//Int(1))
    println("**************************************************************")
    println("Rate limit: $(ratelimit)")
    println("Keep going...")
    ip = getsockname(tcp)[1]
    println("ip: $(ip)")
    rate = Float64(ratelimit.num)
    println("rate: $(rate)")
    rl = get!(ratelimits, ip, HTTP.Servers.MbedTLS.SSLConfig(rate, Dates.now()))
    println("rl: $(rl)")
    update!(rl, ratelimit)
    if rl.allowance > rate
        rl.allowance = rate
    end
    if rl.allowance < 1.0
        #@debug "discarding connection due to rate limiting"
        return false
    else
        rl.allowance -= 1.0
    end
    println("Leaving...")
    return true
end
