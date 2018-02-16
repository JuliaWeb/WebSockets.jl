info("Loading HttpServer methods...")

export WebSocketHandler


"""
Responds to a WebSocket handshake request.
Checks for required headers and subprotocols; sends Response(400) if they're missing or bad. Otherwise, transforms client key into accept value, and sends Reponse(101).
Function returns true for accepted handshakes.
"""
function websocket_handshake(request,client)
    if !haskey(request.headers, "Sec-WebSocket-Key")
        Base.write(client.sock, HttpServer.Response(400))
        return false
    end
    if get(request.headers, "Sec-WebSocket-Version", "13") != "13"
        response = HttpServer.Response(400)
        response.headers["Sec-WebSocket-Version"] = "13"
        Base.write(client.sock, response)
        return false
    end

    key = request.headers["Sec-WebSocket-Key"]
    if length(base64decode(key)) != 16 # Key must be 16 bytes
        Base.write(client.sock, HttpServer.Response(400))
        return false
    end
  resp_key = generate_websocket_key(key)

  response = HttpServer.Response(101)
  response.headers["Upgrade"] = "websocket"
  response.headers["Connection"] = "Upgrade"
  response.headers["Sec-WebSocket-Accept"] = resp_key
 
  if haskey(request.headers, "Sec-WebSocket-Protocol") 
      if hasprotocol(request.headers["Sec-WebSocket-Protocol"])
          response.headers["Sec-WebSocket-Protocol"] =  request.headers["Sec-WebSocket-Protocol"]
      else
          Base.write(client.sock, HttpServer.Response(400))
          return false
      end
  end 
  
  Base.write(client.sock, response)
  return true
end

""" Implement the WebSocketInterface, for compatilibility with HttpServer."""
struct WebSocketHandler <: HttpServer.WebSocketInterface
    handle::Function
end

"""
Performs handshake. If successfull, establishes WebSocket type and calls
handler with the WebSocket and the original request. On exit from handler, closes websocket. No return value.
"""
function HttpServer.handle(handler::WebSocketHandler, req::HttpServer.Request, client::HttpServer.Client)
    websocket_handshake(req, client) || return
    sock = WebSocket(client.sock,true)
    handler.handle(req, sock)
    if isopen(sock) 
        try
        close(sock)
        end
    end
end

function HttpServer.is_websocket_handshake(handler::WebSocketHandler, req::HttpServer.Request)
    is_get = req.method == "GET"
    # "upgrade" for Chrome and "keep-alive, upgrade" for Firefox.
    is_upgrade = contains(lowercase(get(req.headers, "Connection", "")),"upgrade")
    is_websockets = lowercase(get(req.headers, "Upgrade", "")) == "websocket"
    return is_get && is_upgrade && is_websockets
end