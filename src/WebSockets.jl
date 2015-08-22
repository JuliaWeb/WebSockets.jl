module WebSockets

# This module implements the server side of the WebSockets protocol. Some
# things would need to be added to implement a WebSockets client, such as
# masking of sent frames.
#
# WebSockets expects to be used with HttpServer to provide the HttpServer
# for accepting the HTTP request that begins the opening handshake. WebSockets
# implements a subtype of the WebSocketInterface from HttpServer; this means
# that you can create a WebSocketsHandler and pass it into the constructor for
# an http server.
#
# Future improvements:
# 1. Logging of refused requests and closures due to bad behavior of client.
# 2. Better error handling (should we always be using "error"?)
# 3. Unit tests with an actual client -- to automatically test the examples.
# 4. Send close messages with status codes.
# 5. Allow users to receive control messages if they want to.

using HttpCommon
using HttpServer
using Codecs
using Nettle
using Compat

export WebSocket,
       WebSocketHandler,
       write,
       read,
       close,
       send_ping,
       send_pong

# A WebSocket is a wrapper over a TcpSocket. It takes care of wrapping outgoing
# data in a frame and unwrapping (and concatenating) incoming data.
type WebSocket
  id::Int
  socket::Base.TcpSocket
  is_closed::Bool
  sent_close::Bool

  function WebSocket(id::Int,socket::Base.TcpSocket)
    new(id,socket, !isopen(socket), false)
  end
end

# WebSocket Frames
#
#      0                   1                   2                   3
#      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#     +-+-+-+-+-------+-+-------------+-------------------------------+
#     |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
#     |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
#     |N|V|V|V|       |S|             |   (if payload len==126/127)   |
#     | |1|2|3|       |K|             |                               |
#     +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
#     |     Extended payload length continued, if payload len == 127  |
#     + - - - - - - - - - - - - - - - +-------------------------------+
#     |                               |Masking-key, if MASK set to 1  |
#     +-------------------------------+-------------------------------+
#     | Masking-key (continued)       |          Payload Data         |
#     +-------------------------------- - - - - - - - - - - - - - - - +
#     :                     Payload Data continued ...                :
#     + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
#     |                     Payload Data continued ...                |
#     +---------------------------------------------------------------+
#
# Opcode values
#  *  %x0 denotes a continuation frame
#  *  %x1 denotes a text frame
#  *  %x2 denotes a binary frame
#  *  %x3-7 are reserved for further non-control frames
#
#  *  %x8 denotes a connection close
#  *  %x9 denotes a ping
#  *  %xA denotes a pong
#  *  %xB-F are reserved for further control frames

# Constructs a frame from the arguments and sends it on the provided socket.
function send_fragment(ws::WebSocket, islast::Bool, data::Array{Uint8}, opcode=0b0001)
  l = length(data)
  b1::Uint8 = (islast ? 0b1000_0000 : 0b0000_0000) | opcode
  if l <= 125
    write(ws.socket,b1)
    write(ws.socket,UInt8(l))
    write(ws.socket,data)
  elseif l <= typemax(Uint16)
    write(ws.socket,b1)
    write(ws.socket,UInt8(126))
    write(ws.socket,hton(UInt16(l)))
    write(ws.socket,data)
  elseif l <= typemax(Uint64)
    write(ws.socket,b1)
    write(ws.socket,UInt8(127))
    write(ws.socket,hton(UInt64(l)))
    write(ws.socket,data)
  else
    error("Attempted to send too much data for one websocket fragment\n")
  end
end

# A version of send_fragment for text data.
function send_fragment(ws::WebSocket, islast::Bool, data::ByteString, opcode=0b0001)
  send_fragment(ws, islast, data.data, opcode)
end

# Write text data; will be sent as one frame.
function Base.write(ws::WebSocket,data::ByteString)
  if ws.is_closed
    @show ws
    error("Attempted write to closed WebSocket\n")
  end
  send_fragment(ws, true, data)
end

# Write binary data; will be sent as one frmae.
function Base.write(ws::WebSocket, data::Array{Uint8})
  if ws.is_closed
    @show ws
    error("attempt to write to closed WebSocket\n")
  end
  send_fragment(ws, true, data, 0b0010)
end

# Send a ping message, optionally with data.
function send_ping(ws::WebSocket, data = "")
  send_fragment(ws, true, data, 0x9)
end

# Send a pong message, optionally with data.
function send_pong(ws::WebSocket, data = "")
  send_fragment(ws, true, data, 0xA)
end

# Send a close message.
function Base.close(ws::WebSocket)
    send_fragment(ws, true, "", 0x8)
    ws.is_closed = true
    while true
      wsf = read_frame(ws)
      is_control_frame(wsf) || continue
      wsf.opcode == 0x8 || continue
      break
    end
    close(ws.socket)
end

# A WebSocket is closed if the underlying TCP socket closes, or if we send or
# receive a close message.
Base.isopen(ws::WebSocket) = !ws.is_closed


# Represents one (received) message frame.
type WebSocketFragment
  is_last::Bool
  rsv1::Bool
  rsv2::Bool
  rsv3::Bool
  opcode::Uint8  # This is actually a Uint4 value.
  is_masked::Bool
  payload_len::Uint64
  maskkey::Vector{Uint8}  # This will be 4 bytes on frames from the client.
  data::Vector{Uint8}  # For text messages, this is a ByteString.
end

# This constructor handles conversions from bytes to bools.
function WebSocketFragment(
   fin::Uint8
  ,rsv1::Uint8
  ,rsv2::Uint8
  ,rsv3::Uint8
  ,opcode::Uint8
  ,masked::Uint8
  ,payload_len::Uint64
  ,maskkey::Vector{Uint8}
  ,data::Vector{Uint8})

  WebSocketFragment(
      fin != 0
    , rsv1 != 0
    , rsv2 != 0
    , rsv3 != 0
    , opcode
    , masked != 0
    , payload_len
    , maskkey
    , data)
end

# Control frames have opcodes with the highest bit = 1.
is_control_frame(msg::WebSocketFragment) = (msg.opcode & 0b0000_1000) > 0

# Respond to pings, ignore pongs, respond to close.
function handle_control_frame(ws::WebSocket,wsf::WebSocketFragment)
  if wsf.opcode == 0x8  # %x8 denotes a connection close.
    send_fragment(ws, true, "", 0x8)
    ws.is_closed = true
    wait(ws.socket.closenotify)
  elseif wsf.opcode == 0x9  # %x9 denotes a ping.
    send_pong(ws,wsf.data)
  elseif wsf.opcode == 0xA  # %xA denotes a pong.
    # Nothing to do here; no reply is needed for a pong message.
  else  # %xB-F are reserved for further control frames
    error("Unknown opcode $(wsf.opcode)")
  end
end

# Read a frame: turn bytes from the websocket into a WebSocketFragment.
function read_frame(ws::WebSocket)
  a = read(ws.socket,Uint8)
  fin    = a & 0b1000_0000 >>> 7  # If fin, then is final fragment
  rsv1   = a & 0b0100_0000  # If not 0, fail.
  rsv2   = a & 0b0010_0000  # If not 0, fail.
  rsv3   = a & 0b0001_0000  # If not 0, fail.
  opcode = a & 0b0000_1111  # If not known code, fail.
  # TODO: add validation somewhere to ensure rsv, opcode, mask, etc are valid.

  b = read(ws.socket,Uint8)
  mask = b & 0b1000_0000 >>> 7  # If not 1, fail.

  payload_len::Uint64 = b & 0b0111_1111
  if payload_len == 126
    payload_len = ntoh(read(ws.socket,Uint16))  # 2 bytes
  elseif payload_len == 127
    payload_len = ntoh(read(ws.socket,Uint64))  # 8 bytes
  end

  maskkey = Array(Uint8,4)
  for i in 1:4
   maskkey[i] = read(ws.socket,Uint8)
  end

  data = Array(Uint8, payload_len)
  for i in 1:payload_len
    d = read(ws.socket, Uint8)
    d = d $ maskkey[mod(i - 1, 4) + 1]
    data[i] = d
  end

  return WebSocketFragment(fin,rsv1,rsv2,rsv3,opcode,mask,payload_len,maskkey,data)
end

# Read one non-control message from a WebSocket. Any control messages that are
# read will be handled by the handle_control_frame function. This function will
# not return until a full non-control message has been read. If the other side
# doesn't ever complete it's message, this function will never return. Only the
# data (contents/body/payload) of the message will be returned from this
# function.
function Base.read(ws::WebSocket)
  if ws.is_closed
    error("Attempt to read from closed WebSocket")
  end
  frame = read_frame(ws)

  # Handle control (non-data) messages.
  if is_control_frame(frame)
    # Don't return control frames; they're not interesting to users.
    handle_control_frame(ws,frame)

    # Recurse to return the next data frame.
    return read(ws)
  end

  # Handle data message that uses multiple fragments.
  if !frame.is_last
    return vcat(frame.data, read(ws))
  end

  return frame.data
end

#
# WebSocket Handshake
#

# This function transforms a websocket client key into the server's accept
# value. This is done in three steps:
#   1. Concatenate key with magic string from RFC.
#   2. SHA1 hash the resulting base64 string.
#   3. Encode the resulting number in base64.
# This function then returns the string of the base64-encoded value.
function generate_websocket_key(key)
  h = HashState(SHA1)
  update!(h, key*"258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
  bytestring(encode(Base64, digest!(h)))
end

# Responds to a WebSocket handshake request.
# Checks for required headers; sends Response(400) if they're missing or bad.
# Otherwise, transforms client key into accept value, and sends Reponse(101).
function websocket_handshake(request,client)
  if !haskey(request.headers, "Sec-WebSocket-Key")
    Base.write(client.sock, Response(400))
    return
  end
  if get(request.headers, "Sec-WebSocket-Version", "13") != "13"
    response = Response(400)
    response.headers["Sec-WebSocket-Version"] = "13"
    Base.write(client.sock, response)
    return
  end

  key = request.headers["Sec-WebSocket-Key"]
  if length(decode(key)) != 16 # Key must be 16 bytes
    Base.write(client.sock, Response(400))
    return
  end
  resp_key = generate_websocket_key(key)

  response = Response(101)
  response.headers["Upgrade"] = "websockets"
  response.headers["Connection"] = "Upgrade"
  response.headers["Sec-WebSocket-Accept"] = resp_key
  Base.write(client.sock, response)
end

# Implement the WebSocketInterface, for compatilibility with HttpServer.
immutable WebSocketHandler <: HttpServer.WebSocketInterface
    handle::Function
end

import HttpServer: handle, is_websocket_handshake
function handle(handler::WebSocketHandler, req::Request, client::HttpServer.Client)
    websocket_handshake(req, client)
    sock = WebSocket(client.id, client.sock)
    handler.handle(req, sock)
    isopen(sock) && close(sock)
end
function is_websocket_handshake(handler::WebSocketHandler, req::Request)
    is_get = req.method == "GET"
    is_upgrade = lowercase(get(req.headers, "Connection", false)) == "upgrade"
    is_websockets = lowercase(get(req.headers, "Upgrade", false)) == "websocket"
    return is_get && is_upgrade && is_websockets
end

end # module WebSockets
