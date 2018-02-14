info("Loading HTTP methods...")

function open(f::Function, url; binary=false, verbose=false, kw...)

    key = base64encode(rand(UInt8, 16))

    headers = [
        "Upgrade" => "websocket",
        "Connection" => "Upgrade",
        "Sec-WebSocket-Key" => key,
        "Sec-WebSocket-Version" => "13"
    ]

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
        f(WebSocket(io,false))
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
    f(WebSocket(io, true))
end

function check_upgrade(http)
    if !HTTP.hasheader(http, "Upgrade", "websocket")
        throw(WebSocketError(0, "Expected \"Upgrade: websocket\"!\n$(http.message)"))
    end

    if !HTTP.hasheader(http, "Connection", "upgrade")
        throw(WebSocketError(0, "Expected \"Connection: upgrade\"!\n$(http.message)"))
    end
end

function is_upgrade(r::HTTP.Message)
    (r isa HTTP.Request && r.method == "GET" || r.status == 101) &&
    HTTP.hasheader(r, "Connection", "upgrade") &&
    HTTP.hasheader(r, "Upgrade", "websocket")
end

# function listen(f::Function, host::String="localhost", port::UInt16=UInt16(8081); binary=false, verbose=false)
#     HTTP.listen(host, port; verbose=verbose) do http
#         upgrade(f, http; binary=binary)
#     end
# end

