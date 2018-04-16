__precompile__()
"""
    WebSockets
This module implements the server side of the WebSockets protocol. Some
things would need to be added to implement a WebSockets client, such as
masking of sent frames.

WebSockets expects to be used with HttpServer to provide the HttpServer
for accepting the HTTP request that begins the opening handshake. WebSockets
implements a subtype of the WebSocketInterface from HttpServer; this means
that you can create a WebSocketsHandler and pass it into the constructor for
an http server.

    Future improvements:
1. Logging of refused requests and closures due to bad behavior of client.
2. Better error handling (should we always be using "error"?)
3. Unit tests with an actual client -- to automatically test the examples.
4. Send close messages with status codes.
5. Allow users to receive control messages if they want to.
"""
module WebSockets

import MbedTLS: digest, MD_SHA1
using Requires 

export WebSocket,
       write,
       read,
       close,
       send_ping,
       send_pong

const TCPSock = Base.TCPSocket

@enum ReadyState CONNECTED=0x1 CLOSING=0x2 CLOSED=0x3

""" Buffer writes to socket till flush (sock)"""
init_socket(sock) = Base.buffer_writes(sock) 


struct WebSocketClosedError <: Exception end
Base.showerror(io::IO, e::WebSocketClosedError) = print(io, "Error: client disconnected")

struct WebSocketError <: Exception
    status::Int16
    message::String
end

"""
A WebSocket is a wrapper over a TcpSocket. It takes care of wrapping outgoing
data in a frame and unwrapping (and concatenating) incoming data.
"""
mutable struct WebSocket{T <: IO} <: IO
    socket::T
    server::Bool
    state::ReadyState

    function WebSocket{T}(socket::T,server::Bool) where T
        init_socket(socket)
        new(socket, server, CONNECTED)
    end
end
WebSocket(socket,server) = WebSocket{typeof(socket)}(socket,server)

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
""" *  %x0 denotes a continuation frame"""
const OPCODE_CONTINUATION = 0x00
""" *  %x1 denotes a text frame"""
const OPCODE_TEXT = 0x1
""" *  %x2 denotes a binary frame"""
const OPCODE_BINARY = 0x2
#  *  %x3-7 are reserved for further non-control frames
#
""" *  %x8 denotes a connection close"""
const OPCODE_CLOSE = 0x8
""" *  %x9 denotes a ping"""
const OPCODE_PING = 0x9
""" *  %xA denotes a pong"""
const OPCODE_PONG = 0xA
# *  %xB-F are reserved for further control frames


"""
Handshakes with subprotocols are rejected by default.
Add to supported SUBProtocols through e.g.
# Examples
```
   WebSockets.addsubproto("special-protocol")
   WebSockets.addsubproto("json")
```   
In the general websocket handler function, specialize 
further by checking 
# Example
```
if get(wsrequest.headers, "Sec-WebSocket-Protocol", "") = "special-protocol"
    specialhandler(websocket)
else
    generalhandler(websocket)
end
```
"""
const SUBProtocols= Array{String,1}() 

"Used in handshake. See SUBProtocols"
hasprotocol(s::AbstractString) = in(s, SUBProtocols)

"Used to specify handshake response. See SUBProtocols"
function addsubproto(name)
    push!(SUBProtocols, string(name))
    return true
end
""" 
    write_fragment(io, islast, opcode, hasmask, data::Array{UInt8})
Write the raw frame to a bufffer
"""
function write_fragment(io::IO, islast::Bool, opcode, hasmask::Bool, data::Vector{UInt8})
    l = length(data)
    b1::UInt8 = (islast ? 0b1000_0000 : 0b0000_0000) | opcode

    mask::UInt8 = hasmask ? 0b1000_0000 : 0b0000_0000

    write(io, b1)
    if l <= 125
        write(io, mask | UInt8(l))
    elseif l <= typemax(UInt16)
        write(io, mask | UInt8(126))
        write(io, hton(UInt16(l)))
    elseif l <= typemax(UInt64)
        write(io, mask | UInt8(127))
        write(io, hton(UInt64(l)))
    else
        error("Attempted to send too much data for one websocket fragment\n")
    end
    if hasmask
        if opcode == OPCODE_TEXT
            data = copy(data) # Avoid masking Strings bytes in place
        end
        write(io,mask!(data))
    end
    write(io, data)
end

""" Write without interruptions"""
function locked_write(io::IO, islast::Bool, opcode, hasmask::Bool, data::Vector{UInt8})
    isa(io, TCPSock) && lock(io.lock)
    try
        write_fragment(io, islast, opcode, hasmask, data)
    finally
        if isa(io, TCPSock)
            flush(io)
            unlock(io.lock)
        end
    end
end

""" Write text data; will be sent as one frame."""
function Base.write(ws::WebSocket,data::String)
    locked_write(ws.socket, true, OPCODE_TEXT, !ws.server, Vector{UInt8}(data)) # Vector{UInt8}(String) will give a warning in v0.7.
end

""" Write binary data; will be sent as one frame."""
function Base.write(ws::WebSocket, data::Array{UInt8})
    locked_write(ws.socket, true, OPCODE_BINARY, !ws.server, data)
end


function write_ping(io::IO, hasmask, data = UInt8[])
    locked_write(io, true, OPCODE_PING, hasmask, data)
end
""" Send a ping message, optionally with data."""
send_ping(ws, data...) = write_ping(ws.socket, !ws.server, data...)


function write_pong(io::IO, hasmask, data = UInt8[])
    locked_write(io, true, OPCODE_PONG, hasmask, data)
end
""" Send a pong message, optionally with data."""
send_pong(ws, data...) = write_pong(ws.socket, !ws.server, data...)

""" 
    close(ws::WebSocket)
Send a close message.
"""
function Base.close(ws::WebSocket)
    if isopen(ws)
        ws.state = CLOSING
        locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, UInt8[])

        # Wait till the other end responds with an OPCODE_CLOSE. This process is
        # complicated by potential blocking reads on the WebSocket in other Tasks
        # which may receive the response control frame. Synchronization of who is
        # responsible for closing the underlying socket is done using the
        # WebSocket's state. When this side initiates closing the connection it is
        # responsible for cleaning up, when the other side initiates the close the
        # read method is
        #
        # The exception handling is necessary as read_frame will error when the
        # OPCODE_CLOSE control frame is received by a potentially blocking read in
        # another Task
        try
            while isopen(ws)
                wsf = read_frame(ws)
                # ALERT: stuff might get lost in ether here    
                if is_control_frame(wsf) && (wsf.opcode == OPCODE_CLOSE)
                    ws.state = CLOSED
                end
            end
            if isopen(ws.socket)
                close(ws.socket)
            end
        catch exception
            !isa(exception, EOFError) && rethrow(exception)
        end
    else
        ws.state = CLOSED
    end
end

"""
    isopen(WebSocket)-> Bool
A WebSocket is closed if the underlying TCP socket closes, or if we send or
receive a close message.
"""
Base.isopen(ws::WebSocket) = (ws.state != CLOSED) && isopen(ws.socket)

Base.eof(ws::WebSocket) = (ws.state == CLOSED) || eof(ws.socket)

""" Represents one (received) message frame."""
mutable struct WebSocketFragment
    is_last::Bool
    rsv1::Bool
    rsv2::Bool
    rsv3::Bool
    opcode::UInt8  # This is actually a UInt4 value.
    is_masked::Bool
    payload_len::UInt64
    maskkey::Vector{UInt8}  # This will be 4 bytes on frames from the client.
    data::Vector{UInt8}  # For text messages, this is a String.
end

""" This constructor handles conversions from bytes to bools."""
function WebSocketFragment(
     fin::UInt8
    , rsv1::UInt8
    , rsv2::UInt8
    , rsv3::UInt8
    , opcode::UInt8
    , masked::UInt8
    , payload_len::UInt64
    , maskkey::Vector{UInt8}
    , data::Vector{UInt8})

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

""" Control frames have opcodes with the highest bit = 1."""
is_control_frame(msg::WebSocketFragment) = (msg.opcode & 0b0000_1000) > 0

""" Respond to pings, ignore pongs, respond to close."""
function handle_control_frame(ws::WebSocket,wsf::WebSocketFragment)
    if wsf.opcode == OPCODE_CLOSE
        info("$(ws.server ? "Server" : "Client") received OPCODE_CLOSE")
        ws.state = CLOSED
        locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, UInt8[])
    elseif wsf.opcode == OPCODE_PING
        info("$(ws.server ? "Server" : "Client") received OPCODE_PING")
        send_pong(ws,wsf.data)
    elseif wsf.opcode == OPCODE_PONG
        info("$(ws.server ? "Server" : "Client") received OPCODE_PONG")
        # Nothing to do here; no reply is needed for a pong message.
    else  # %xB-F are reserved for further control frames
        error("Unknown opcode $(wsf.opcode)")
    end
end

""" Read a frame: turn bytes from the websocket into a WebSocketFragment."""
function read_frame(ws::WebSocket)
    ab = read(ws.socket,2)
    #= 
    TODO error handling decision...
    Browsers will seldom close in the middle of writing to a socket,
    but other clients often do, and the stacktraces can be very long.
    ab is often not assigned.
    We could check for and throw a WebSocketError:
    isassigned(ab) && throw(WebSocketError(0, "Socket closed while reading"))
    This is often triggered:
    BoundsError: attempt to access 0-element Array{UInt8,1} at index [1]
    ...and sometimes also:
    BoundsError: attempt to access 0-element Array{UInt8,1} at index [2]
    If the last message is thrown here, ab has been assigned but only partly
    read.
    =# 
    a = ab[1]
    fin    = a & 0b1000_0000 >>> 7  # If fin, then is final fragment
    rsv1   = a & 0b0100_0000  # If not 0, fail.
    rsv2   = a & 0b0010_0000  # If not 0, fail.
    rsv3   = a & 0b0001_0000  # If not 0, fail.
    opcode = a & 0b0000_1111  # If not known code, fail.
    # TODO: add validation somewhere to ensure rsv, opcode, mask, etc are valid.

    b = ab[2]
    mask = b & 0b1000_0000 >>> 7
    hasmask = mask != 0

    payload_len::UInt64 = b & 0b0111_1111
    if payload_len == 126
        payload_len = ntoh(read(ws.socket,UInt16))  # 2 bytes
    elseif payload_len == 127
        payload_len = ntoh(read(ws.socket,UInt64))  # 8 bytes
    end

    maskkey = hasmask ? read(ws.socket,4) : UInt8[]

    data = read(ws.socket,Int(payload_len))
    hasmask && mask!(data,maskkey)

    return WebSocketFragment(fin,rsv1,rsv2,rsv3,opcode,mask,payload_len,maskkey,data)
end

"""
    read(ws::WebSocket)
Read one non-control message from a WebSocket. Any control messages that are
read will be handled by the handle_control_frame function. This function will
not return until a full non-control message has been read. If the other side
doesn't ever complete its message, this function will never return. Only the
data (contents/body/payload) of the message will be returned from this
function.
"""
function Base.read(ws::WebSocket)
    if !isopen(ws)
        error("Attempt to read from closed WebSocket")
    end
    frame = read_frame(ws)

    # Handle control (non-data) messages.
    if is_control_frame(frame)
        # Don't return control frames; they're not interesting to users.
        handle_control_frame(ws,frame)
        return frame.data
    end

    # Handle data message that uses multiple fragments.
    if !frame.is_last
        return vcat(frame.data, read(ws))
    end

    return frame.data
end

"""
    WebSocket Handshake Procedure
`generate_websocket_key(key)` transforms a websocket client key into the server's accept
value. This is done in three steps:
1. Concatenate key with magic string from RFC.
2. SHA1 hash the resulting base64 string.
3. Encode the resulting number in base64.
This function then returns the string of the base64-encoded value.
"""
function generate_websocket_key(key)
    hashkey = "$(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    return base64encode(digest(MD_SHA1, hashkey))
end

function mask!(data, mask=rand(UInt8, 4))
    for i in 1:length(data)
        data[i] = data[i] ⊻ mask[((i-1) % 4)+1]
    end
    return mask
end

@require HTTP include("HTTP.jl")
@require HttpServer include("HttpServer.jl")
end # module WebSockets
