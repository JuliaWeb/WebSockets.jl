# Included in runtests at the end. 

# Tool up with a function hierarchy. The browsers are already trying to reach it.
const WEBSOCKETS = Dict{Int, WebSockets.WebSocket}()
const WEBSOCKETS_SUBPROTOCOL = Dict{Int, WebSockets.WebSocket}()
const RECEIVED_MSGS = Dict{Int, Vector{String}}()
global noofresponders = 0
include("server_functions.jl") 

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
if Sys.is_windows()
	include("open_windows_browsers.jl")
else
	include("open_unix_os_browsers.jl")
end 
noofbrowsers = open_all_browsers()
info("Out of google chrome, firefox, iexplore and safari, spawned ", noofbrowsers)

const CLOSEAFTER = Base.Dates.Second(15)
t0 = now()
while now()-t0 < CLOSEAFTER && length(keys(RECEIVED_MSGS)) < noofbrowsers * 2
	sleep(1)
end 
info(length(keys(RECEIVED_MSGS)), " received messages.")
info("Tell the special ones to initiate a close.")
for (ke, va) in WEBSOCKETS_SUBPROTOCOL
	writeto(ke, "YOU hang up!")
end

sleep(10)
info("Closing down after ", now()-t0, " including 10 seconds pause.")
countstillopen = 0
for (ke, va) in WEBSOCKETS
	if isopen(va) 
		countstillopen +=1 
		close(va)
	end 
end
sleep(5) 
close(server)
server = nothing 
info("Received messages:")
display(RECEIVED_MSGS)
println()
@test countstillopen == noofresponders
countmessages = 0
for (ke, va) in RECEIVED_MSGS
	countmessages += length(va)
end
@test length(keys(RECEIVED_MSGS)) == noofresponders * 2
@test countmessages == noofresponders * 6
nothing