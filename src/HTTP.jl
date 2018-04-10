info("Loading HTTP methods...")

function open(f::Function, url; binary=false, verbose=false, optionalProtocol = "", kw...)

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

function upgrade(f::Function, http::HTTP.Stream; binary=false)
    check_upgrade(http)
    if !HTTP.hasheader(http, "Sec-WebSocket-Version", "13")
        throw(WebSocketError(0, "Expected \"Sec-WebSocket-Version: 13\"!\n$(http.message)"))
    end
    HTTP.setstatus(http, 101)
    HTTP.setheader(http, "Upgrade" => "websocket")
    HTTP.setheader(http, "Connection" => "Upgrade")
    key = HTTP.header(http, "Sec-WebSocket-Key")
    HTTP.setheader(http, "Sec-WebSocket-Accept" => generate_websocket_key(key))
    HTTP.startwrite(http)
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

"It is up to the user to call 'is_upgrade'. This provides feedback when that was forgotten."
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

# function listen(f::Function, host::String="localhost", port::UInt16=UInt16(8081); binary=false, verbose=false)
#     HTTP.listen(host, port; verbose=verbose) do http
#         upgrade(f, http; binary=binary)
#     end
# end

