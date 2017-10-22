# 	These functions deal with specified websocket protocols.
#  	Included in server_functions.jl

function ws_test_protocol(ws::WebSockets.WebSocket)
	id = "ws_test_protocol #$(ws.id)\t"
	WEBSOCKETS[ws.id] = ws
	WEBSOCKETS_SUBPROTOCOL[ws.id] = ws
	RECEIVED_MSGS[ws.id] = String[]
	clog(id,  " Entering to read websocket.\n")
	stri = wsmsg_general(ws)
	clog(id,  " Send a message\n")
	push!(RECEIVED_MSGS[ws.id], stri)
	writeto(ws.id, "Here, have a message!")
	clog(id,  " Continue to listen for message\n")
	while isopen(ws) 
		stri = wsmsg_testprotocol(ws)
		push!(RECEIVED_MSGS[ws.id], stri)
	end
	clog(id, "Websocket was closed; exiting read loop\n")
	nothing
end

"""
Listens for the next websocket message. 
"""
function wsmsg_testprotocol(ws::WebSockets.WebSocket)
	id = "wsmsg_testprotocol #$(ws.id)\t"
	clog(id,  " Entering to read websocket.\n")
	stri = ""
	try 
		# Holding here. Cleanup code could work with InterruptException and Base.throwto.
		# This is not considered necessary for the test (and doesn't really work well).
		# So, this may continue running after the test is finished.
		stri = ws|> read  |> String
		clog(id, "Received: \n", :yellow, :bold, stri, "\n")
	catch e
		if typeof(e) == WebSockets.WebSocketClosedError
			clog(id, :green, " Websocket was or is being closed.\n")
		else
			clog(id, "Caught exception..\n", "\t\t", Base.error_color(), e, "\n")
			if isopen(ws) 
				clog(id, "Closing\n")
				close(ws)
			end
		end
	end 
	clog(id, "Exiting\n")
	return stri
end




return nothing
