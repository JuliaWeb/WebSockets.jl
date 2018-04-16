info("Loading HTTP methods...")

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
end
"""
Responds to a WebSocket handshake request. 
If the connection is acceptable, sends status code 101 
and headers according to RFC 6455, then calls
user's handler function f with the connection wrapped in
a WebSocket instance with the open socket as one of the fields.

Closes the websocket after returning from f.

Otherwise responds with '400' and returns nothing.

Calls user's handler function f upon a successful upgrade.
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
        warn(STDERR, "WebSockets.HTTP.upgrade: Caught unhandled error while calling argument function f, the handler / gatekeeper:\n\t")
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

