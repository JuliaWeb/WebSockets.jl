#     These functions deal with unspecified websocket protocols.
#      Included in server_functions.jl


function ws_general(ws::WebSockets.WebSocket)
    id = "ws_general #$(ws.id)\t"
    WEBSOCKETS[ws.id] = ws
    RECEIVED_WS_MSGS[ws.id] = String[]
    RECEIVED_WS_MSGS_LENGTH[ws.id] = Vector{Int64}()
    RECEIVED_WS_MSGS_TIME[ws.id] = Vector{Float64}()
    RECEIVED_WS_MSGS_ALLOCATED[ws.id] = Vector{Int64}()
    sendmsg = "Welcome, general websocket. Our ref.: $(ws.id)"
    clog(id,  " Send: $sendmsg\n")
    while isopen(ws)
        stri = wsmsg_listen(ws)
        push!(RECEIVED_WS_MSGS[ws.id], stri)
        clog(id, "Received: \n", :yellow, :bold, stri, "\n")
        if startswith(stri, "Ping me!")
            send_ping(ws)
            sendmsg = "Your browser just got pinged (and presumably ponged back). Our ref.: $(ws.id)"
            clog(id,  " Sending: $sendmsg\n")
            writeto(ws.id, sendmsg)
        elseif startswith(stri, "ws1 echo: Your browser just got pinged ")
                sendmsg = "Close, wait, and navigate to: browsertest2.html"
            clog(id,  " Sending: $sendmsg\n")
            writeto(ws.id, sendmsg)
        end
    end
    clog(id, "Websocket $(ws.id) was closed; exits handler.\n")
    nothing
end

function writeto(wsid::Int, message)
    if haskey(WEBSOCKETS, wsid)
        write(WEBSOCKETS[wsid], message)
    end
    return nothing
end

"""
Listens for the next websocket message
"""
function wsmsg_listen(ws::WebSockets.WebSocket)
    id = "wsmsg_listen #$(ws.id)\t"
    clog(id,  " Listening...\n")
    stri = ""
    data = Vector{UInt8}()
    t = 0.0
    allocbytes = 0
    try
        # Holding here. Cleanup code could work with InterruptException and Base.throwto.
        # This is not considered necessary for the test (and doesn't really work well).
        # So, this may continue running after the test is finished.
        push!(RECEIVED_WS_MSGS_TIME[ws.id], t)
        push!(RECEIVED_WS_MSGS_ALLOCATED[ws.id], allocbytes)
        data , t, allocbytes = @timed ws|> read
        push!(RECEIVED_WS_MSGS_LENGTH[ws.id], length(data))
        push!(RECEIVED_WS_MSGS_TIME[ws.id], t)
        push!(RECEIVED_WS_MSGS_ALLOCATED[ws.id], allocbytes)
        stri = data |> String
    catch e
        if typeof(e) == WebSockets.WebSocketClosedError
            clog(id, :green, " Websocket was or is being closed.\n")
        else
            clog(id, "Caught exception..\n", "\t\t", :red, e, "\n")
            if isopen(ws)
                clog(id, "Closing\n")
                close(ws)
            end
        end
    end
    return stri
end
return nothing