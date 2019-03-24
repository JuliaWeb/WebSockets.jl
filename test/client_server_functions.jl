# included in client_serverWS_test.jl
# and in client_listen_test.jl

if !@isdefined SUBPROTOCOL
    const SUBPROTOCOL = "Server start the conversation"
    const SUBPROTOCOL_CLOSE = "Server start the conversation and close it from within websocket handler"
end
addsubproto(SUBPROTOCOL)
addsubproto(SUBPROTOCOL_CLOSE)
if !@isdefined(PORT)
    const PORT = 8000
    const SURL = "127.0.0.1"
    const EXTERNALWSURI = "ws://echo.websocket.org"
    const EXTERNALHTTP = "http://httpbin.org/ip"
    const MSGLENGTHS = [0 , 125, 126, 127, 2000]
end

"""
`test_handler` is called by WebSockets inner function `_servercoroutine` for all accepted http requests
that are not upgrades. We don't check what's actually requested.
"""
test_handler(req::HTTP.Request) = HTTP.Response(200, "OK")

"""
`test_wshandler` is called by WebSockets inner function
`_servercoroutine` for all http requests that
    1) qualify as an upgrade,
    2) request a subprotocol we claim to support
Based on the requested subprotocol, test_wshandler calls
    `initiatingws`
        or
    `echows`
"""
function test_wshandler(req::HTTP.Request, ws::WebSocket)
    WebSockets.origin(req) != "" && @error "test_wshandler, got origin header as from a browser."
    WebSockets.target(req) != "/" && @error "test_wshandler, got origin header as in a POST request."
    if WebSockets.subprotocol(req) == SUBPROTOCOL
        initiatingws(ws, msglengths = MSGLENGTHS)
    elseif WebSockets.subprotocol(req) == SUBPROTOCOL_CLOSE
        initiatingws(ws, msglengths = MSGLENGTHS,  closebeforeexit = true)
    else
        echows(ws)
    end
end

"""
`echows` is called by
    - `test_wshandler` (in which case ws will be a server side websocket)
    or
    - 'WebSockets.open' (in which case ws will be a client side websocket)

Takes an open websocket.
    1)  Reads a message
    2)  Echoes it
    3)  Repeats until the websocket closes, or a read fails.
The tests will be captured if the function is run on client side.
If started by the server side, this is called as part of a coroutine.
Therefore, test results will not propagate to the enclosing test scope.
"""
function echows(ws::WebSocket)
    while isopen(ws)
        data, ok = readguarded(ws)
        if ok
            if writeguarded(ws, data)
                @test true
            else
                break
            end
        else
            if !isopen(ws)
                break
            else
                break
            end
        end
    end
end

"""
`initiatingws` is called by
    - `test_wshandler` (in which case ws will be a server side websocket)
    or
    - 'WebSockets.open' (in which case ws will be a client side websocket)

Takes
    - an open websocket
    keyword arguments
    - msglengths = a vector of message lengths, defaults to MSGLENGTHS
    - closebeforeexit, defaults to false

1) Pings, but does not check for received pong. There will be console output from the pong side.
2) Send a message of specified length
3) Checks for an exact echo
4) Repeats 2-4 until no more message lenghts are specified.
"""
function initiatingws(ws::WebSocket; msglengths = MSGLENGTHS, closebeforeexit = false)
    send_ping(ws)
    # No ping check made, the above will just output some info message.

    # We need to yield since we are sharing the same process as the task on the
    # other side of the connection.
    # The other side must be reading in order to process the ping-pong.
    yield()
    for slen in msglengths
        test_str = Random.randstring(slen)
        forcecopy_str = test_str |> collect |> copy |> join
        if writeguarded(ws, test_str)
            yield()
            readback, ok = readguarded(ws)
            if ok
                # if run by the server side, this test won't be captured.
                if String(readback) == forcecopy_str
                    @test true
                else
                    if ws.server == true
                        @error "initatews, echoed string of length ", slen, " differs from sent "
                    else
                        @test false
                    end
                end
            else
                # if run by the server side, this test won't be captured.
                if ws.server == true
                    @error "initatews, couldn't read ", ws, " length sent is ", slen
                else
                    @test false
                end
            end
        else
            @test false
        end
    end
    closebeforeexit && close(ws, statusnumber = 1000)
end

test_serverws = WebSockets.ServerWS(
    HTTP.RequestHandlerFunction(test_handler),
    WebSockets.WSHandlerFunction(test_wshandler))

function startserver(serverws=test_serverws;url=SURL, port=PORT, verbose=false)
    servertask = @async WebSockets.serve(serverws,url,port,verbose)
    while !istaskstarted(servertask);yield();end
    if isready(serverws.out)
        # capture errors, if any were made during the definition.
        @error take!(serverws.out)
    end
    serverws
end
