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
    global noofresponders
    id = "server_functions.httphandle\t"
    clog(id, :cyan, request, "\n")
    if request.method=="GET"
        if request.resource =="/favicon.ico"
            response =  HttpServer.FileResponse(joinpath(@__DIR__, "favicon.ico"))
        else
            response =  HttpServer.FileResponse(joinpath(@__DIR__, "browsertest.html"))
            noofresponders += 1
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
        clog(id, "subprotocol spec: \n\t\t\t",
                    :yellow, "Sec-WebSocket-Protocol => ", wsrequest.headers["Sec-WebSocket-Protocol"],"\n")
        if     wsrequest.headers["Sec-WebSocket-Protocol"] == "websocket-testprotocol"
            clog(id, "Websocket-testprotocol, calling handler\n")
            ws_test_protocol(websocket)
            clog(id, "Websocket-testprotocol, exiting handler\n")
        else
            clog(id, Base.error_color(), "Unknown sub protocol let through WebSockets.jl, not responding further. \n")
        end
    else
        clog(id, "General websocket, calling handler\n")
        ws_general(websocket)
        clog(id, "General websocket, exiting handler\n")
    end
    clog(id, "Exiting \n")
    nothing
end


function start_ws_server_async()
    id = "server_functions.start_ws_server\t"
    # Specify this subprotocol is to be let through to websockethandle:
    WebSockets.addsubproto("websocket-testprotocol")
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
