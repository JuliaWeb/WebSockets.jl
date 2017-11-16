#     These functions deal with specified websocket protocols.
#      Included in server_functions.jl


function ws_test_protocol(ws::WebSockets.WebSocket)
    id = "ws_test_protocol #$(ws.id)\t"
    WEBSOCKETS[ws.id] = ws
    WEBSOCKETS_SUBPROTOCOL[ws.id] = ws
    WEBSOCKETS[ws.id] = ws
    RECEIVED_WS_MSGS[ws.id] = String[]
    RECEIVED_WS_MSGS_LENGTH[ws.id] = Vector{Int64}()
    RECEIVED_WS_MSGS_TIME[ws.id] = Vector{Float64}()
    RECEIVED_WS_MSGS_ALLOCATED[ws.id] = Vector{Int64}()
    sendmsg = "Special welcome. Our ref.: $(ws.id)"
    clog(id,  " Sending: $sendmsg\n")
    writeto(ws.id, sendmsg)
    while isopen(ws)
        stri = wsmsg_listen(ws)
        push!(RECEIVED_WS_MSGS[ws.id], stri)
        clog(id, "Received: \n", :yellow, :bold, stri, "\n")
        if startswith(stri, "Ping me!")
            sendmsg = "No ping for you. Our ref.: $(ws.id). Will close on next received message."
            clog(id,  " Sending: $sendmsg\n")
            writeto(ws.id, sendmsg)
        elseif startswith(stri, "ws2 echo: No ping for you.")
            clog(id,  "Closing from server\n")
            close(ws)
        end
    end
    clog(id, "Websocket on subprotocol $(ws.id) was closed; exits handler.\n")
    nothing
end

function ws_test_binary(ws::WebSockets.WebSocket)
    id = "ws_test_binary #$(ws.id)\t"
    WEBSOCKETS[ws.id] = ws
    WEBSOCKETS_BINARY[ws.id] = ws
    RECEIVED_WS_MSGS_LENGTH[ws.id] = Vector{Int64}()
    RECEIVED_WS_MSGS_TIME[ws.id] = Vector{Float64}()
    RECEIVED_WS_MSGS_ALLOCATED[ws.id] = Vector{Int64}()
    width = Int16(0)
    height = Int16(0)
    byteperpixel = Int16(4)
    ub = 0
    clog(id,  " Handler is running \n")
    while isopen(ws)
        data = wsmsg_listen_binary(ws)
        ub = length(data)
        if ub == 6
            # Don't do this like this at home perhaps. Dealing with net endianness by reversing the order of bytes AND arguments..
            byteperpixel, height, width = reinterpret(Int16, reverse(data))
            clog(id, "Received 6 bytes = 3xInt16 custom header: \n\t\t\t\t\t"
                    , :yellow, " height: ", :bold, height
                    , :normal, :yellow, " width: ", :bold, width
                    , :normal, :yellow, " byteperpixel: ", byteperpixel, "\n")
        elseif ub == Int(width) * height * byteperpixel
            clog(id, "Received image data for manipulation, ", div(length(data), 1024),  " kB\n")
            tic()
            ired =  1:4:ub
            igreen =  2:4:ub
            iblue =  3:4:ub
            ialpha = 4:4:ub
            itpquarter = 1:div(ub,4)
            fill!(view(data, ialpha), 0xee)
            fill!(view(data, iblue), 0xff)
            fill!(view(data, intersect(itpquarter, ired)), 0x88)
            rand!(view(data, ired), [0x00, 0x88, 0xff])
            hedata = UInt16.([height, width, 4])
            clog(id, "Manipulated image and made ready in $(toq()*1000) ms. \n\t\tSending header, then image.\n")    
            writeto(ws.id,  reinterpret(UInt8, hedata))
            writeto(ws.id,  data)
        else
            clog(id, "Received unexpected data: \t", :yellow, :bold, length(data), "-element ", typeof(data), "\n")
            clog(id, "expected length: ",  Int(width) * height * byteperpixel
                    , :yellow, " height: ", :bold, height
                    , :normal, :yellow, " width: ", :bold, width
                    , :normal, :yellow, " byteperpixel: ", byteperpixel, "\n")
        end
    end
    clog(id, "Websocket on subprotocol $(ws.id) was closed; exits handler.\n")
    nothing
end
"""
Listens for the next binary websocket message
"""
function wsmsg_listen_binary(ws::WebSockets.WebSocket)
    id = "wsmsg_listen_binary $(ws.id)\t"
    clog(id,  " Binary listening...\n")
    data = Vector{UInt8}()
    t = 0.0
    allocbytes = 0
    try
        # Holding here. Cleanup code could work with InterruptException and Base.throwto.
        # This is not considered necessary for the test (and doesn't really work well).
        # So, this may continue running after the test is finished.
        data , t, allocbytes = @timed ws|> read
        push!(RECEIVED_WS_MSGS_LENGTH[ws.id], length(data))
        push!(RECEIVED_WS_MSGS_TIME[ws.id], t)
        push!(RECEIVED_WS_MSGS_ALLOCATED[ws.id], allocbytes)
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
    return data
end

return nothing
