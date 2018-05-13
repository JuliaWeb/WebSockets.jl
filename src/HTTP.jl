info("Loading HTTP methods...")

"""
Initiate a websocket connection to server defined by url. If the server accepts
the connection and the upgrade to websocket, f is called with an open client type websocket.

e.g. say hello, close and leave 
```julia
import HTTP
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
function open(f::Function, url; verbose=false, optionalProtocol = "", kw...)

    key = base64encode(rand(UInt8, 16))
    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => key,
        "Sec-WebSocket-Version" => "13"
    ]
    if optionalProtocol != ""
        push!(headers, "Sec-WebSocket-Protocol" => optionalProtocol )
    end

    try
        HTTP.open("GET", url, headers;
                reuse_limit=0, verbose=verbose ? 2 : 0, kw...) do http

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
    catch err
        if typeof(err) == Base.UVError
            warn(STDERR, err)
        else 
            rethrow(err)
        end
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
    showerror(err)
    println.(catch_stacktrace()[1:4])
end
```
"""
function upgrade(f::Function, http::HTTP.Stream)
    # Double check the request. is_upgrade should already have been called by user.
    check_upgrade(http)
    browserclient = HTTP.hasheader(http, "Origin")
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
    if length(base64decode(key)) != 16 # Key must be 16 bytes
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
    try
        if applicable(f, Dict(http.message.headers), ws)
            f(Dict(http.message.headers), ws)
        else
            f(ws)
        end
    catch err
        warn("WebSockets.HTTP.upgrade: Caught unhandled error while calling argument function f, the handler / gatekeeper:\n\t")
        mt = typeof(f).name.mt
        fnam = splitdir(string(mt.defs.func.file))[2]
        print_with_color(:yellow, STDERR, "f = ", string(f) * " at " * fnam * ":" * string(mt.defs.func.line) * "\nERROR:\t")
        showerror(STDERR, err, backtrace())
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
        throw(WebSocketError(0, "Check upgrade: Expected \"Connection => upgrade or Connection => keep alive, upgrad\"!\n$(http.message)"))
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

