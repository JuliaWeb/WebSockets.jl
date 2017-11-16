include("functions_log_test.jl")
include("handler_functions_events.jl")
include("handler_functions_websockets_general_test.jl")
include("handler_functions_websockets_subprotocol_test.jl")
"""
Although a websocket could be opened from a file on any server or just from the browser
working on the file system, we open a test http server.
The term 'handler' is relative to point of view. We make a hierachy of functions and then give
the types defined in HttpServer references to the functions. More commonly, anonymous functions
are used.
"""
function httphandle(request::Request, response::Response)
    global n_responders
    id = "server_functions.httphandle\t"
    clog(id, :cyan, request, "\n")
    if request.method=="GET"
        if request.resource =="/favicon.ico"
            response =  HttpServer.FileResponse(joinpath(@__DIR__, "favicon.ico"))
            push!(response.headers, "Connection" => "close")

        elseif startswith(request.resource, "/browser")
            response =  HttpServer.FileResponse(joinpath(@__DIR__, splitdir(request.resource)[2]))
            if request.resource == "/browsertest.html"
                n_responders += 1
            else
                push!(response.headers, "Connection" => "close")
            end
        else
            response = Response(404, "$id, can't serve $request.resource.")
        end
    else
        response = Response(404, "$id, unexpected request.")
    end
    clog(id, response, "\n")
    return response
end

"""
Inner function for WebsocketHandler. Called on opening a new websocket after
the handshake procedure is finished.
The request contains info which can be used for additional delegation or gatekeeping.
Function never exits until the websocket is closed, but calls are made asyncronously.
"""
function websockethandle(wsrequest::Request, websocket::WebSocket)
    id = "server_functions.websockethandle\t"
    clog(id, :cyan, wsrequest, "\t", :yellow, websocket, "\n")
    if haskey(wsrequest.headers,"Sec-WebSocket-Protocol")
        if wsrequest.headers["Sec-WebSocket-Protocol"] == "websocket-testprotocol"
            ws_test_protocol(websocket)
        elseif wsrequest.headers["Sec-WebSocket-Protocol"] == "websocket-test-binary"
            ws_test_binary(websocket)
        else
            clog(id, :red, "Unknown sub protocol let through, not responding further to #$(websocket.id). \n")
        end
    else
        ws_general(websocket)
    end
    clog(id, "Exiting \n")
    nothing
end


function start_ws_server_async()
    id = "server_functions.start_ws_server\t"
    # Specify this subprotocol is to be let through to websockethandle:
    WebSockets.addsubproto("websocket-testprotocol")
    WebSockets.addsubproto("websocket-test-binary")
    # Tell HttpHandler which functions to spawn when something happens.
    httpha = HttpHandler(httphandle)
    httpha.events["error"]  = ev_error
    httpha.events["listen"] = ev_listen
    httpha.events["connect"] = ev_connect
    httpha.events["close"] = ev_close
    httpha.events["write"] = ev_write
    httpha.events["reset"] = ev_reset
    # Pack the websockethandle function in an interface container
    wsh = WebSocketHandler(websockethandle)
    server = Server(httpha, wsh )
    clog(id, "Server to be started:\n", server )
    servertask = @async run( server, 8080)
    clog(id, "Server listening on localhost:8080\n")
    server
end
"Closes websockets and server; other existing sockets, if any, remain open."
function closeall()
    if isdefined(:WEBSOCKETS)
        for va in values(WEBSOCKETS)
            if isopen(va)
                close(va)
            end
        end
        if isdefined(:server)
            close(server)
        end
    end
end
"Counts the number of open websocket in WEBSOCKETS dictionary"
function count_open_websockets()
    count = 0
    for w in values(WEBSOCKETS)
        if isopen(w)
            count += 1
        end
    end
    count
end
