using WebSockets
function client_one_message(ws)
    printstyled(stdout, "\nws|client input >  ", color=:green)
    msg = readline(stdin)
    if writeguarded(ws, msg)
        msg, stillopen = readguarded(ws)
        println("Received:", String(msg))
        if stillopen
            println("The connection is active, but we leave. WebSockets.jl will close properly.")
        else
            println("Disconnect during reading.")
        end
    else
        println("Disconnect during writing.")
    end
end
function main()
    while true
        println("\nSuggestion: Run 'minimal_server.jl' in another REPL")
        println("\nWebSocket client side. WebSocket URI format:")
        println("ws:// host [ \":\" port ] path [ \"?\" query ]")
        println("Example:\nws://127.0.0.1:8080")
        println("Where do you want to connect? Empty line to exit")
        printstyled(stdout, color = :green,  "\nclient_repl_input >  ")
        wsuri = readline(stdin)
        wsuri == "" && break
        res = WebSockets.open(client_one_message, wsuri)
    end
    println("Have a nice day")
end

main()
