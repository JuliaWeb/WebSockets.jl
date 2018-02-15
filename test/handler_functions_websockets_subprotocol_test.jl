#     These functions deal with specified websocket protocols.
#      Included in server_functions.jl


function ws_test_protocol(ws::WebSockets.WebSocket)
    id = cid = ""
    while isopen(ws)
        id, msg = wsmsg_listen(ws)
        cid = "ws_test_protocol $(id)\t"
        # WEBSOCKETS_SUBPROTOCOL[id] = ws
        sendmsg = "Special welcome. Our ref.: $(id)"
        clog(cid,  " Sending: $sendmsg\n")
        writeto(id, sendmsg)
        clog(cid, "Received: \n", :yellow, :bold, msg, "\n")
        if startswith(msg, "Ping me!")
            sendmsg = "No ping for you. Our ref.: $(id). Will close on next received message."
            clog(cid,  " Sending: $sendmsg\n")
            writeto(id, sendmsg)
        elseif startswith(msg, "ws2 echo: No ping for you.")
            clog(cid,  "Closing from server\n")
            close(ws)
        end
    end
    clog(cid, "Websocket on subprotocol $(id) was closed; exits handler.\n")
    nothing
end

function ws_test_binary(ws::WebSockets.WebSocket)
    id = cid = ""
    width = Int16(0)
    height = Int16(0)
    byteperpixel = Int16(4)
    ub = 0
    while isopen(ws)
        id, data = wsmsg_listen_binary(ws)
        cid = "ws_test_binary $(id)\t"
        clog(cid,  " Handler is running \n")
        ub = length(data)
        if ub == 6
            # Don't do this like this at home perhaps. Dealing with net endianness by reversing the order of bytes AND arguments..
            byteperpixel, height, width = reinterpret(Int16, reverse(data))
            clog(cid, "Received 6 bytes = 3xInt16 custom header: \n\t\t\t\t\t"
                    , :yellow, " height: ", :bold, height
                    , :normal, :yellow, " width: ", :bold, width
                    , :normal, :yellow, " byteperpixel: ", byteperpixel, "\n")
        elseif ub == Int(width) * height * byteperpixel
            clog(cid, "Received image data for manipulation, ", div(length(data), 1024),  " kB\n")
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
            writeto(id,  reinterpret(UInt8, hedata))
            writeto(id,  data)
        else
            clog(cid, "Received unexpected data: \t", :yellow, :bold, length(data), "-element ", typeof(data), "\n")
            clog(cid, "expected length: ",  Int(width) * height * byteperpixel
                    , :yellow, " height: ", :bold, height
                    , :normal, :yellow, " width: ", :bold, width
                    , :normal, :yellow, " byteperpixel: ", byteperpixel, "\n")
        end
    end
    clog(cid, "Websocket on subprotocol $(id) was closed; exits handler.\n")
    nothing
end
"""
Listens for the next binary websocket message
"""
function wsmsg_listen_binary(ws::WebSockets.WebSocket)
    id = cid = ""
    data = UInt8[]
    try
        # Holding here. Cleanup code could work with InterruptException and Base.throwto.
        # This is not considered necessary for the test (and doesn't really work well).
        # So, this may continue running after the test is finished.
        id = String(read(ws))
        data , t, allocbytes = @timed read(ws)
        cid = "wsmsg_listen_binary $(id)\t"
        clog(cid,  " Binary listening...\n")

        if !haskey(WEBSOCKETS,id) 
            clog(:red,"Pushing WS...\n")
            WEBSOCKETS[id] = ws
            WEBSOCKETS_BINARY[id] = ws
            RECEIVED_WS_MSGS_LENGTH[id] = Vector{Int64}()
            RECEIVED_WS_MSGS_TIME[id] = Vector{Float64}()
            RECEIVED_WS_MSGS_ALLOCATED[id] = Vector{Int64}()
        end
        push!(RECEIVED_WS_MSGS_LENGTH[id], length(data))
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
    return id, data
end

return nothing
