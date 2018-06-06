include("functions_log_test.jl")
include("handler_functions_events.jl")
include("handler_functions_websockets_general_test.jl")
include("handler_functions_websockets_subprotocol_test.jl")

"""
This function returns responses to http requests.
For serving the HTML javascript pages which then open WebSocket clients.
"""
function httphandle(request::Request, response::Response)
    global n_responders
    id = "server_functions.httphandle\t"
    clog(id, :cyan, request, "\n")
    if request.method=="GET"
        if request.resource =="/favicon.ico"
            response =  HttpServer.FileResponse(joinpath(@__DIR__, "favicon.ico"))
        elseif startswith(request.resource, "/browser")
            response =  HttpServer.FileResponse(joinpath(@__DIR__, splitdir(request.resource)[2]))
            if request.resource == "/browsertest.html"
                n_responders += 1
            end
        else
            response = Response(404, "$id, can't serve $request.resource.")
        end
    else
        response = Response(404, "$id, unexpected request.")
    end
    clog(id, response, "\n")
    push!(response.headers, "Connection" => "close")
    return response
end

"""
When a connection performs the handshake successfully, this function 
is called as a separate task. Based on inspecting the request that was 
accepted as an upgrade, it in turn calls one of three functions.
The function call does not return until it is time to close the websocket. 
"""
function gatekeeper(wsrequest::Request, websocket::WebSocket)
    id = "server_functions.gatekeeper\t"
    clog(id, :cyan, wsrequest, "\t", :yellow, websocket, "\n")
    if subprotocol(wsrequest) == "websocket-testprotocol"
        ws_test_protocol(websocket)
    elseif subprotocol(wsrequest) == "websocket-test-binary"
        ws_test_binary(websocket)
    elseif subprotocol(wsrequest) != ""
        clog(id, :red, "Unknown sub protocol let through, not responding further. \n")
    else
        ws_general(websocket)
    end
    clog(id, "Exiting \n")
    nothing
end


function start_ws_server_async()
    id = "server_functions.start_ws_server\t"
    # Specify this subprotocol is to be let through to gatekeeper:
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
    # Pack the gatekeeper function in a recognizable function wrapper
    wsh = WebSocketHandler(gatekeeper)
    server = Server(httpha, wsh )
    clog(id, "Server to be started:\n", server )
    servertask = @async run( server, 8080)
    clog(id, "Server listening on 127.0.0.1:8080\n")
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
