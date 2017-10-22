# Provides extra verbose output for testing
function ev_error(client::Client, args...)
	id = "events.ev_error\t"
	#clog(id, Base.warn_color(), "client $client ", :normal, " ", args..., "\n")
end 
function ev_listen(port, args...)	
	id = "events.ev_listen\t"
	#clog(id, :light_yellow, " from port ", :bold, port , :normal, " ", args..., " that was all I think. \n")
end 
function ev_connect(client::Client, args...) 
	id = "events.ev_connect\t"
	#clog(id, :light_yellow, " from client ", :bold, client , :normal, " ", args..., "\n")
end 	
function ev_close(client::Client, args...) 
	id = "events.ev_close\t"
	#clog(id, :light_yellow, " from client ", :bold, client , :normal, " ", args..., "\n")
end 
function ev_write(client::Client, response::Response) 
	id = "events.ev_write\t"
	#clog(id, "to ",:light_yellow, client , :bold, client , :normal, "\n", response, "\n")
end 
function ev_reset(client::Client, response::Response) 
	id = "events.ev_reset\t"
	#clog(id, :light_yellow, " client ", :bold, client , :normal, "\n", response, "\n")
end 
