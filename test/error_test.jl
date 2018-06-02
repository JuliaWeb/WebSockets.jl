# included in runtests.jl

# As per June 2018, there is no
# way we can process errors thrown
# by tasks generated by HttpServer
# or by HTTP, for example ECONNRESET.
# 
# Try to provide user with relevant and 
# concise output.
using Base.Test
import HTTP
import WebSockets: ServerWS,
        serve,
        open

const THISPORT = 8092
info("Start a ws|server which doesn't read much at all. Close from client side. The
      close handshake is aborted after $(WebSockets.TIMEOUT_CLOSEHANDSHAKE) seconds...")
server_WS = WebSockets.ServerWS(
    HTTP.HandlerFunction(req-> HTTP.Response(200)), 
    WebSockets.WebsocketHandler(ws-> sleep(16)))
@schedule WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
sleep(3)
URL = "ws://127.0.0.1:$THISPORT"
res = WebSockets.open((_)->nothing, URL);
@test res.status == 101
put!(server_WS.in, HTTP.Servers.KILL)

#=
Activate test when there is a decent way to capture errors
in tasks generated by server package

server_WS = WebSockets.ServerWS(HTTP.HandlerFunction(req-> HTTP.Response(200)), 
                                WebSockets.WebsocketHandler() do ws_serv
                                                while isopen(ws_serv)
                                                    readguarded(ws_serv)
                                                end
                                            end
                                            )
@schedule WebSockets.serve(server_WS, "127.0.0.1", THISPORT, false)
# attempt to read from closed websocket.
WebSockets.open(URL) do ws_client
        close(ws_client)
        try
        read(ws_client)
        catch
        end
    end;

function wsh(ws)
    close(ws)
    read(ws)
end
# improve output of error, the details don't emerge
WebSockets.open(wsh, URL)

=#