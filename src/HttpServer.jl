info("Loading HttpServer methods...")

export WebSocketHandler

"""
Called by HttpServer. Responds to a WebSocket handshake request. 
If the connection is acceptable, sends status code 101 
and headers according to RFC 6455. Function returns
a WebSocket instance with the open socket as one of the fields.

Otherwise responds with '400' and returns false.

Any other response means 'decline', so a reason can be given.
The function returns 'true' to HttpServer, which then calls the
user's websocket handler.

It is recommended to do further checks of the upgrade request in the
user handler function.
   - "Origin" header: Included by clients in browsers, e.g: => "http://localhost:8000"
   - "Sec-WebSocket-Protocol" header: If included, e.g.: => "myOwnProtocol"
   -  "Sec-WebSocket-Extensions" => "permessage-deflate"

A WebSocketHandler may include:
  .function
  .acceptURI
  .acceptsubprotocol
  . acceptsource
  . acceptOrin.
Typical headers:
  -
   "Connection"               => "keep-alive, Upgrade"
   "Sec-WebSocket-Version"    => "13"
   "http_minor"               => "1"
   "Keep-Alive"               => "1"
   "User-Agent"               => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:59.0) Gecko/20100101 Fi…
   "Accept-Encoding"          => "gzip, deflate"
   "Cache-Control"            => "no-cache"
   "Origin"                   => "http://localhost:8000"
   "Sec-WebSocket-Key"        => "R9b6CHWxy9cg3H+1WuCFCA=="
   "Sec-WebSocket-Protocol"   => "relay_frontend"
   "Sec-WebSocket-Extensions" => "permessage-deflate"
   "Host"                     => "localhost:8000"
   "Upgrade"                  => "websocket"
   "Pragma"                   => "no-cache"
   "http_major"               => "1"
   "Accept"                   => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
   "Accept-Language"          => "en-US,en;q=0.5"
 """
function websocket_handshake(request, client)
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
    # TODO move this part further up, similar to in HTTP.jl
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

"""
WebSocketHandler(f::Function) <: HttpServer.WebSocketInterface

A simple Function-wrapper for HttpServer.

The provided argument should be of the form 
    `f(Request, WebSocket) => nothing`

Request is intended for gatekeeping, ref. RFC 6455 section 10.1.
WebSocket is for reading, writing and exiting when finished.

Take note of the very similar WebsocketHandler (no capital 'S'), which is a subtype of HTTP.
"""
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

"""
Fast checking for websockets vs http requests, performed on all new HttpServer requests.
Similar to is_upgrade(r::HTTP.Message)
"""
function HttpServer.is_websocket_handshake(handler::WebSocketHandler, req::HttpServer.Request)
    if req.method == "GET"
        if ismatch(r"upgrade"i, get(req.headers, "Connection", ""))
            if lowercase(get(req.headers, "Upgrade", "")) == "websocket"
                return true
            end
        end
    end
    return false
end
# Inline docs in WebSockets.jl
target(req::HttpServer.Request) = req.resource
subprotocol(req::HttpServer.Request) = get(req.headers, "Sec-WebSocket-Protocol", "")
origin(req::HttpServer.Request) = get(req.headers, "Origin", "")