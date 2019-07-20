# This example starts a coroutine for websocket handling, 
# which again splits input and output on different tasks.
# Note that if 
using WebSockets
inbox = Channel{String}(10)
outbox = Channel{String}(10)

ws_task = @async WebSockets.with_logger(WebSocketLogger(stderr, Base.CoreLogging.Debug)) do
    WebSockets.open("wss://echo.websocket.org") do ws
        @sync begin
            inbox_task = @async try
                while true #!eof(ws)
                    in_data, success = readguarded(ws)
                    success || break
                    in_msg = String(in_data)
                    @wslog in_msg
                    put!(inbox, in_msg)
                end
            finally
                @debug ws " Now closing outbox, to be sure"
                close(outbox)
            end
            outbox_task = @async try
                for outmsg in outbox
                    isopen(ws) && writeguarded(ws, outmsg) || break
                end
            finally
                @debug "Closing " ws
                close(ws)
            end
        end
    end
end

put!(outbox, "Hello")
put!(outbox, "World!")

@show take!(inbox)
@show take!(inbox)

close(outbox) # close(outbox) causes outbox_task to call close(ws)
wait(ws_task)

@show istaskdone(ws_task)
@show Base.istaskfailed(ws_task)
nothing