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
function test_handler(stream::HTTP.Streams.Stream)
    request = stream.message
    request.response = HTTP.Response(200, "OK")
    request.response.request = request
    write(stream, request.response.body)
end

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
experiment with nonblocking reads
"""
function readguarded_nonblocking(ws; sleep = 2)
    chnl= Channel{Tuple{Vector{UInt8}, Bool}}(1)
    # Read, output put to Channel for type stability
    function _readinterruptable(c::Channel{Tuple{Vector{UInt8}, Bool}})
        try
            @error "preparing to readguarded..."
            #sleep !=0 && sleep(sleep)
            put!(chnl, readguarded(ws))
            @error "preparing to readguarded done"
        catch err
            @debug sprint(showerror, err)
            errtyp = typeof(err)
            ok = !(errtyp != InterruptException &&
                   errtyp != Base.IOError &&
                   errtyp != HTTP.IOExtras.IOError &&
                   errtyp != Base.BoundsError &&
                   errtyp != Base.EOFError &&
                   errtyp != Base.ArgumentError)
            # Output a dummy frame that is not a control frame.
            put!(chnl, (Vector{UInt8}(), ok))
        end
    end
    # Start reading as a task. Will not return if there is nothing to read
    rt = @async _readinterruptable(chnl)
    bind(chnl, rt)
    yield()
    # Define a task for throwing interrupt exception to the (possibly blocked) read task.
    # We don't start this task because it would never return
    killta = @task try
        sleep(30)
        @error "will be killing _readinterruptable"
        throwto(rt, InterruptException())
    catch
    end
    # We start the killing task. When it is scheduled the second time,
    # we pass an InterruptException through the scheduler.
    try
        schedule(killta, InterruptException(), error = false)
    catch
    end
    # We now have content on chnl, and no additional tasks.
    take!(chnl)
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
        @debug "reading from socket"
        data, ok = readguarded_nonblocking(ws)
        #data, ok = readguarded(ws)
        isempty(data) && @error("empty data ok=$(ok)")
        if ok
            @debug "writing to socket"
            if writeguarded(ws, data)
                @test true
            else
                break
            end
        else
            @debug "failed to read"
            if !isopen(ws)
            	@debug "socket is not open"
                break
            else
            	@debug "yet socket is open"
                break
            end
        end
        sleep(0.01)
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
    WebSockets.RequestHandlerFunction(test_handler),
    WebSockets.WSHandlerFunction(test_wshandler))

function startserver(serverws=test_serverws;url=SURL, port=PORT, verbose=false)
    servertask = @async WebSockets.serve(serverws,url,port,verbose)
    while !istaskstarted(servertask);yield();end
    if isready(serverws.out)
        # capture errors, if any were made during the definition.
        @error take!(serverws.out)
    end
    serverws, servertask
end

function Base.close(serverws::WebSockets.ServerWS, servertask::Task)
    close(serverws)
    @info "waiting for servertask to finish"
    wait(servertask)
    @info "servertask done"
    return
end