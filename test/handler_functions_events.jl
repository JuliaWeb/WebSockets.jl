# Provides extra verbose output for testing
function ev_error(client::Client, args...)
    id = "events.ev_error\t"
    clog(id, :yellow, "client $client ", :normal, " ", args..., "\n")
end
function ev_listen(port, args...)
    id = "events.ev_listen\t"
    #clog(id, :yellow, " from port ", :bold, port , :normal, " ", args..., " that was all I think. \n")
    nothing
end
function ev_connect(client::Client, args...)
    id = "events.ev_connect\t"
    clog(id, :yellow, " from client ", :bold, client , :normal, " ", args..., "\n")
end
function ev_close(client::Client, args...)
    id = "events.ev_close\t"
    clog(id, :yellow, " from client ", :bold, client , :normal, " ", args..., "\n")
end
function ev_write(client::Client, response::Response)
    id = "events.ev_write\t"
    clog(id, "to ", :yellow, :bold, client , :normal, "\n", response, "\n")
end
function ev_reset(client::Client, response::Response)
    id = "events.ev_reset\t"
    clog(id, :yellow, " client ", :bold, client , :normal, "\n", response, "\n")
end
