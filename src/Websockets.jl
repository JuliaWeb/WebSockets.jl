module Websockets

using Httplib
using Http
export Websocket,
       WebsocketHandler,
       write,
       read,
       close

type Websocket
  id::Int
  socket::TcpSocket
end

#
# Websocket Packets
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
#      *  %x0 denotes a continuation frame
#      *  %x1 denotes a text frame
#      *  %x2 denotes a binary frame
#      *  %x3-7 are reserved for further non-control frames
#      *  %x8 denotes a connection close
#      *  %x9 denotes a ping
#      *  %xA denotes a pong
#      *  %xB-F are reserved for further control frames

function send_fragment(ws::Websocket, islast::Bool, data)
  l = length(data)
  b1::Uint8 = (islast ? 0b1000_0001 : 0b0000_0001) #always send text

  if l <= 125
    write(ws.socket,b1)
    write(ws.socket,uint8(l))
    write(ws.socket,data)
  elseif l <= typemax(Uint16)
    write(ws.socket,b1)
    write(ws.socket,uint8(126))
    write(ws.socket,uint16(l))
    write(ws.socket,data)
  elseif l <= typemax(Uint64)
    write(ws.socket,b1)
    write(ws.socket,uint8(127))
    write(ws.socket,uint64(l))
    write(ws.socket,data)
  else
    error("Attempted to send too much data for one websocket fragment")
  end
end

import Base.write
function write(ws::Websocket,data)
  println("sending")
  #assume data fits in one fragment
  send_fragment(ws,true,data)
end

type WebsocketFragment
  is_last::Bool
  rsv1::Bool
  rsv2::Bool
  rsv3::Bool
  opcode::Uint8 #really, Uint4
  is_masked::Bool
  payload_len::Uint64
  maskkey::Array{Uint8,4} #Union{Array{Uint8,4}, Nothing}
  data::Array{Uint8} #ByteString
end

function WebsocketFragment(fin,rsv1,rsv2,rsv3,opcode,masked,payload_len,maskkey,data)
  return WebsocketFragment( bool(fin)
    , bool(rsv1)
    , bool(rsv2)
    , bool(rsv3)
    , opcode
    , bool(masked)
    , payload_len
    , maskkey
    , data)
end

function is_control_frame(msg::WebsocketFragment)
  return bool((msg.opcode & 0b0000_1000) >>> 3)
  # if that bit is set (1), then this is a control frame.
end

function handle_control_frame(ws::Websocket,wsf::WebsocketFragment)
  #just drop it on the floor.
end

import Base.read
function read(ws::Websocket)
  a = read(ws.socket,Uint8)
  fin    = a & 0b1000_0000 >>> 7 #if fin, then is final fragment
  rsv1   = a & 0b0100_0000 #if not 0, fail.
  rsv2   = a & 0b0010_0000 #if not 0, fail.
  rsv3   = a & 0b0001_0000 #if not 0, fail.
  opcode = a & 0b0000_1111 #if not known code, fail.

  b = read(ws.socket,Uint8)
  mask = b & 0b1000_0000 >>> 7 #if not 1, fail.

  payload_len::Uint64 = b & 0b0111_1111
  if payload_len == 126
    payload_len = ntoh(read(ws.socket,Uint16)) #2 bytes
  elseif payload_len == 127
    payload_len = ntoh(read(ws.socket,Uint64)) #8 bytes
  end

  maskkey = Array(Uint8,4)
  for i in 1:4
   maskkey[i] = read(ws.socket,Uint8)
  end

  data = Array(Uint8, payload_len)
  for i in 1:payload_len
    d = read(ws.socket, Uint8)
    d = d $ maskkey[mod(i - 1, 4) + 1]
    print("$(convert(Char,d))")
    data[i] = d
  end

  #handle control (non-data) messages
  #@show wsf = WebsocketFragment(fin,rsv1,rsv2,rsv3,opcode,mask,payload_len,maskkey,data)
  #if is_control_frame(wsf)
  #  @show handle_control_frame(ws,wsf)
  #  #return read(ws)
  #end

  return data
end

function close(ws::Websocket)
  println("...send close frame")
  println("...make sure we don't send anything else")
  println("...wait for their close frame, then close the Tcpsocket")
end

#
# Websocket Handshake
#

#parse http request for special key
get_websocket_key(request::Request) = begin
  return request.headers["Sec-WebSocket-Key"]
end

char2digit(c::Char) = '0' <= c <= '9' ? c-'0' : lowercase(c)-'a'+10

hex2bytes(s::ASCIIString) =
  [ uint8(char2digit(s[i])<<4 | char2digit(s[i+1])) for i=1:2:length(s) ]

const base64chars = ['A':'Z','a':'z','0':'9','+','/']

function base64(x::Uint8, y::Uint8, z::Uint8)
  n = int(x)<<16 | int(y)<<8 | int(z)
  base64chars[(n >> 18)            + 1],
  base64chars[(n >> 12) & 0b111111 + 1],
  base64chars[(n >>  6) & 0b111111 + 1],
  base64chars[(n      ) & 0b111111 + 1]
end

function base64(x::Uint8, y::Uint8)
  a, b, c = base64(x, y, 0x0)
  a, b, c, '='
end

function base64(x::Uint8)
  a, b = base64(x, 0x0, 0x0)
  a, b, '=', '='
end

function base64(v::Array{Uint8})
  n = length(v)
  w = Array(Uint8,4*iceil(n/3))
  j = 0
  for i = 1:3:n-2
    w[j+=1], w[j+=1], w[j+=1], w[j+=1] = base64(v[i], v[i+1], v[i+2])
  end
  tail = n % 3
  if tail > 0
    w[j+=1], w[j+=1], w[j+=1], w[j+=1] = base64(v[end-tail+1:end]...)
  end
  ASCIIString(w)
end

generate_websocket_key(key) = begin
  magicstring = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @show resp_key = readall(`echo -n $key$magicstring` | `openssl dgst -sha1`)
  @show m = match(r"(?:\([^)]*\)=\s)?(.+)$", resp_key)
  bytes = hex2bytes(m.captures[1])
  return base64(bytes)
end

# perform the handshake if it's a websocket request
websocket_handshake(request,client) = begin

  key = get_websocket_key(request)
  resp_key = generate_websocket_key(key)

  #TODO: use a proper HTTP response type
  response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "
  Base.write(client.sock,"$response$resp_key\r\n\r\n")
end

immutable WebsocketHandler <: Http.WebsocketInterface
    handle::Function
end

import Http: handle, is_websocket_handshake
function handle(handler::WebsocketHandler, req::Request, client::Http.Client)
    websocket_handshake(req, client)
    handler.handle(req, Websocket(client.id, client.sock))
end
function is_websocket_handshake(handler::WebsocketHandler, req::Request)
    get(req.headers, "Upgrade", false) == "websocket"
end

end # module Websockets
