# A server and a client help each other counting to 10.
using WebSockets
import WebSockets.with_logger
import WebSockets.string_with_env_ws
const COUNTTO = 10
const PORT = 8090
addsubproto("count")
# This overloading only affects the
# first argument to logging macros, and only when
# logging with WebSocketLogger
function string_with_env_ws(env, req::WebSockets.Request)
    iob = IOBuffer()
    ioc = IOContext(iob, env)
    printstyled(ioc, "Request: ", color= :yellow)
    printstyled(ioc, req.method, color = :bold)
    print(ioc, " ")
    printstyled(ioc, req.target, color = :cyan)
    subprot = subprotocol(req)
    if subprot != ""
        print(ioc, "\n")
        orig = WebSockets.origin(req)
        print(ioc, "\nOrigin: " * orig * " Subprotocol: " * subprot)
    end
    if length(req.headers) > 0
        print(ioc, " ")
        printstyled(ioc, "\tHeaders: ", color = :cyan)
        for (name, value) in req.headers
            print(ioc, "$name => $value \t")
        end
    end
    String(take!(iob))
end

httphandler(req::WebSockets.Request) = WebSockets.Response(200, "OK")

function coroutine_count(ws)
    @wslog ("Enter coroutine, ", ws)
    success = true
    protocolfollowed = true
    counter = 0
    # Server sends 1
    if ws.server
        counter += 1
        if !writeguarded(ws, Array{UInt8}([counter]))
            @warn ws, " could not write first message"
            protocolfollowed = false
        end
    end


    while isopen(ws) && protocolfollowed && counter < COUNTTO && success
        protocolfollowed = false
        data, success = readguarded(ws)
        if success
            OUTDATA = data
            if length(data) == 1
                if data[1] == counter + 1
                    protocolfollowed = true
                    counter += 2
                    @wslog ws, " Counter: ", counter
                    writeguarded(ws, Array{UInt8}([counter]))
                else
                    @error ws, " unexpected: ", counter
                end
            else
                protocolfollowed = false
                @warn (ws, " wrong message length: "), length(data)
                @wslog "Data is type ", typeof(data)
                @wslog data
            end
        end
    end
    if protocolfollowed
        @wslog (ws, " finished counting to $COUNTTO, exiting")
    else
        @wslog "Exiting ", ws, " Counter: ", counter
    end
end

function gatekeeper(req, ws)
    @wslog req
    if subprotocol(req) != ""
        coroutine_count(ws)
    else
        @wslog "No subprotocol"
    end
end

function serve_task(logger= WebSocketLogger(stderr, WebSockets.Logging.Debug))
    server = WebSockets.ServerWS(httphandler, gatekeeper)
    task = @async   with_logger(logger) do
        WebSockets.serve(server, port = PORT)
    end
    @info "http://localhost:$PORT"
    return server, task
end

server, sertask = serve_task()

clitask = @async with_logger(WebSocketLogger(stderr, WebSockets.Logging.Debug)) do
        WebSockets.open(coroutine_count, "ws://localhost:$PORT", subprotocol = "count")
    end

@async begin
    sleep(5)
    println("Time out 5 s, closing server")
    put!(server.in, "Close")
    nothing
end
