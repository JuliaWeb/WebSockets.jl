# Included in runtests at the end.

const WEBSOCKETS = Dict{Int, WebSockets.WebSocket}()
const WEBSOCKETS_SUBPROTOCOL = Dict{Int, WebSockets.WebSocket}()
const RECEIVED_WS_MSGS = Dict{Int, Vector{String}}()
global noofresponders = 0

include("functions_server.jl")

server = start_ws_server_async()

# Give the server 5 seconds to get going.
sleep(5)
info("We waited 5 seconds after starting the server.")
for (ke, va) in WEBSOCKETS
    if isopen(va)
        info("Somebody opened a websocket during that time. Closing it now.")
        close(va)
    end
end

info("This OS is ", Sys.KERNEL)
include("functions_open_browsers.jl")
noofbrowsers = open_all_browsers()
const CLOSEAFTER = Base.Dates.Second(15)
t0 = now()
while now()-t0 < CLOSEAFTER && length(keys(RECEIVED_WS_MSGS)) < noofbrowsers * 2
    sleep(1)
end
info("Received messages on ", length(keys(RECEIVED_WS_MSGS)), " sockets.")
info("Tell the special sockets to initiate a close.")
for (ke, va) in WEBSOCKETS_SUBPROTOCOL
    writeto(ke, "YOU hang up!")
end

sleep(10)
info("Closing down after ", now()-t0, " including 10 seconds pause.")
countstillopen = 0
for (ke, va) in WEBSOCKETS
    if isopen(va)
        info(" Websocket to close: ", va)
        countstillopen +=1
        close(va)
    end
end
sleep(5)
close(server)
server = nothing
info("Openened $noofbrowsers, from which $noofresponders requested the HTML page.")
info("Received messages for each websocket:")
display(RECEIVED_WS_MSGS)
println()
@test countstillopen == noofresponders
countmessages = 0
for (ke, va) in RECEIVED_WS_MSGS
    countmessages += length(va)
end
@test length(keys(RECEIVED_WS_MSGS)) == noofresponders * 2
@test countmessages == noofresponders * 6
nothing
