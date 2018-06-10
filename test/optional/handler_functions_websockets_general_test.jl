#     These functions deal with unspecified websocket protocols.
#      Included in server_functions.jl


function ws_general(ws::WebSockets.WebSocket)
    id = cid = ""
    while isopen(ws)
        id, msg = wsmsg_listen(ws)
        cid = "ws_general     $(id)\t"
        # RECEIVED_WS_MSGS[id] = String[]
        # RECEIVED_WS_MSGS_LENGTH[id] = Vector{Int64}()
        # RECEIVED_WS_MSGS_TIME[id] = Vector{Float64}()
        # RECEIVED_WS_MSGS_ALLOCATED[id] = Vector{Int64}()
        sendmsg = "Welcome, general websocket. Our ref.: $(id)"
        clog(cid,  " Send: $sendmsg\n")
        clog(cid, "Received: \n", :yellow, :bold, msg, "\n")
        if startswith(msg, "Ping me!")
            send_ping(ws)
            sendmsg = "Your browser just got pinged (and presumably ponged back). Our ref.: $(id)"
            clog(cid,  " Sending: $sendmsg\n")
            writeto(id, sendmsg)
        elseif startswith(msg, "ws1 echo: Your browser just got pinged ")
                sendmsg = "Close, wait, and navigate to: browsertest2.html"
            clog(cid,  " Sending: $sendmsg\n")
            writeto(id, sendmsg)
        end
    end
    clog(cid, "Websocket $(id) was closed; exits handler.\n")
    nothing
end

function writeto(wsid::String, message)
    if haskey(WEBSOCKETS, wsid)
        write(WEBSOCKETS[wsid], message)
    end
    return nothing
end

"""
Listens for the next websocket message
"""
function wsmsg_listen(ws::WebSockets.WebSocket)
    id = msg = cid = ""
    try
        # Holding here. 
        data , t, allocbytes = @timed JSON.parse(String(read(ws)))
        id = data["id"]
        msg = data["msg"]
        cid = "wsmsg_listen     $(id)\t"
        clog(cid,  " Listening...\n")
     
        if !haskey(WEBSOCKETS,id) 
            WEBSOCKETS[id] = ws
            WEBSOCKETS_SUBPROTOCOL[id] = ws
            RECEIVED_WS_MSGS[id] = Vector{String}()
            RECEIVED_WS_MSGS_LENGTH[id] = Vector{Int64}()
            RECEIVED_WS_MSGS_TIME[id] = Vector{Float64}()
            RECEIVED_WS_MSGS_ALLOCATED[id] = Vector{Int64}()
        end
        push!(RECEIVED_WS_MSGS[id],msg)
        push!(RECEIVED_WS_MSGS_LENGTH[id], length(msg))
        push!(RECEIVED_WS_MSGS_TIME[id], t)
        push!(RECEIVED_WS_MSGS_ALLOCATED[id], allocbytes)
    catch e
        if typeof(e) == WebSockets.WebSocketClosedError
            clog(cid, :green, " Websocket was or is being closed.\n")
        else
            clog(cid, "Caught exception..\n", "\t\t", :red, e, "\n")
            if isopen(ws)
                clog(cid, "Closing\n")
                close(ws)
            end
        end
    end
    return id, msg
end
return nothing