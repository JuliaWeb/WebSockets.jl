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
       readguarded,
       writeguarded,
       write,
       read,
       close,
       subprotocol,
       target,
       origin,
       send_ping,
       send_pong

const TCPSock = Base.TCPSocket
"A reasonable amount of time"
const TIMEOUT_CLOSEHANDSHAKE = 10.0

@enum ReadyState CONNECTED=0x1 CLOSING=0x2 CLOSED=0x3

""" Buffer writes to socket till flush (sock)"""
init_socket(sock) = Base.buffer_writes(sock)


struct WebSocketClosedError <: Exception
    message::String
end

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
Add to acceptable SUBProtocols through e.g.
```julia
   WebSockets.addsubproto("json")
```
Also see function subprotocol 
"""
const SUBProtocols= Array{String,1}()

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
Send an OPCODE_CLOSE frame, and wait for the same response or until
a reasonable amount of time, $(round(TIMEOUT_CLOSEHANDSHAKE, 1)) s, has passed. 
Data received while closing is dropped.
"""
function Base.close(ws::WebSocket)
    if isopen(ws)
        ws.state = CLOSING
        locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, UInt8[])

        # Wait till the peer responds with an OPCODE_CLOSE while discarding any
        # trailing bytes received.
        #
        # We have no guarantee that the peer is actually reading our OPCODE_CLOSE
        # frame. If not, the peer's state will not change, and we will not receive
        # an aknowledgment of closing. We use a nonblocking read and give up
        # after TIMEOUT_CLOSEHANDSHAKE
        #
        # This process is
        # complicated by potential blocking reads on the WebSocket in other Tasks
        # which may receive the response control frame. Synchronization of who is
        # responsible for closing the underlying socket is done using the
        # WebSocket's state. When this side initiates closing the connection it is
        # responsible for cleaning up, when the other side initiates the close the
        # read method is.
        #
        # The exception handling is necessary as read_frame will error when the
        # OPCODE_CLOSE control frame is received by a potentially blocking read in
        # another Task
        #
        try
            t1 = time() + TIMEOUT_CLOSEHANDSHAKE
            while isopen(ws) && time() < t1
                wsf = readframe_nonblocking(ws)
                if is_control_frame(wsf) && (wsf.opcode == OPCODE_CLOSE)
                    ws.state = CLOSED
                end
            end
            if isopen(ws.socket)
                close(ws.socket)
            end
        catch err
            # Typical 'errors' received while closing down are neglected.
            errtyp = typeof(err)
            errtyp != InterruptException &&
                errtyp != Base.UVError &&
                errtyp != Base.BoundsError &&
                errtyp != Base.EOFError &&
                errtyp != Base.ArgumentError &&
                rethrow(err)
        end
    else
        ws.state = CLOSED
    end
end

"""
    isopen(::WebSocket)-> Bool
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
function handle_control_frame(ws::WebSocket, wsf::WebSocketFragment)
    if wsf.opcode == OPCODE_CLOSE
        #info("ws|$(ws.server ? "server" : "client") received OPCODE_CLOSE")
        ws.state = CLOSED
        try
            locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, UInt8[])
        end
        # If we did not throw an error here, ArgumentError("Stream is closed or unusable") would be thrown later
        throw("ws|$(ws.server ? "server" : "client") received OPCODE_CLOSE, replied with same.")
    elseif wsf.opcode == OPCODE_PING
        info("ws|$(ws.server ? "server" : "client") received OPCODE_PING")
        send_pong(ws, wsf.data)
    elseif wsf.opcode == OPCODE_PONG
        info("ws|$(ws.server ? "server" : "client") received OPCODE_PONG")
        # Nothing to do here; no reply is needed for a pong message.
    else  # %xB-F are reserved for further control frames
        error(" while handle_control_frame(ws|$(ws.server ? "server" : "client"), wsf): Unknown opcode $(wsf.opcode)")
    end
end

""" Read a frame: turn bytes from the websocket into a WebSocketFragment."""
function read_frame(ws::WebSocket)
    # Try to read two bytes. There is no guarantee that two bytes are actually allocated.
    ab = read(ws.socket, 2)
    #=
    Browsers will seldom close in the middle of writing to a socket,
    but other clients often do, and the stacktraces can be very long.
    ab can be assigned, but of length 1. An enclosing try..catch in the calling function
    seems to
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
Typical use:
    msg = String(read(ws))
Read one non-control message from a WebSocket. Any control messages that are
read will be handled by the handle_control_frame function.
Only the data (contents/body/payload) of the message will be returned as a
Vector{UInt8}.

This function will not return until a full non-control message has been read.
"""
function Base.read(ws::WebSocket)
    if !isopen(ws)
        error("Attempt to read from closed WebSocket|$(ws.server ? "server" : "client"). First isopen(ws), or use readguarded(ws)!")
    end
    try
        frame = read_frame(ws)
        # Handle control (non-data) messages.
        if is_control_frame(frame)
            # Don't return control frames; they're not interesting to users.
            handle_control_frame(ws, frame)
            # Recurse to return the next data frame.	
-           return read(ws)
            # The following line from commit 7d5fb4480e17320e0d62cfd60d650381e4fb4960 is a  typo?
            # It would return control frame contents to the user.
            # return frame.data
        end

        # Handle data message that uses multiple fragments.
        if !frame.is_last
            return vcat(frame.data, read(ws))
        end
        return frame.data
    catch err
        try
            errtyp = typeof(err)
            if errtyp <: InterruptException
                # This exception originates from this side. Follow close protocol so as not to irritate the other side.
                close(ws)
                throw(WebSocketClosedError(" while read(ws|$(ws.server ? "server" : "client") received local interrupt exception. Performed closing handshake."))
            elseif  errtyp <: Base.UVError ||
                    errtyp <: Base.BoundsError ||
                    errtyp <: Base.EOFError ||
                    errtyp <: Base.ArgumentError
                throw(WebSocketClosedError(" while read(ws|$(ws.server ? "server" : "client")) $(string(err))"))
            else
                # Unknown cause, give up continued execution.
                # If this happens in a multiple fragment message, the accumulated
                # stacktrace could be very long since read(ws) is iterative.
                rethrow(err)
            end
        finally
            if isopen(ws.socket)
                close(ws.socket)
            end
            ws.state = CLOSED
        end
    end
    return Vector{UInt8}()
end

"""
For the closing handshake, we won't wait indefinitely for non-responsive clients.
Returns a throwaway frame if the socket happens to be empty
"""
function readframe_nonblocking(ws)
    chnl= Channel{WebSocketFragment}(1)
    # Read, output put to Channel for type stability
    function _readinterruptable(c::Channel{WebSocketFragment})
        try
            put!(chnl, read_frame(ws))
        catch
            # Output a dummy frame that is not a control frame.
            put!(chnl, WebSocketFragment(false, false, false, false,
                                UInt8(0), false, UInt64(0),
                                Vector{UInt8}([0x0,0x0,0x0,0x0]),
                                Vector{UInt8}()))
        end
    end
    # Start reading as a task. Will not return if there is nothing to read
    rt = @schedule _readinterruptable(chnl)
    bind(chnl, rt)
    yield()
    # Define a task for throwing interrupt exception to the (possibly blocked) read task.
    # We don't start this task because it would never return
    killta = @task try;Base.throwto(rt, InterruptException());end
    # We start the killing task. When it is scheduled the second time,
    # we pass an InterruptException through the scheduler.
    try;schedule(killta, InterruptException(), error = false);end
    # We now have content on chnl, and no additional tasks.
    take!(chnl)
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

"Used in handshake. See SUBProtocols"
hasprotocol(s::AbstractString) = in(s, SUBProtocols)

"Used to specify acceptable subprotocols. See SUBProtocols"
function addsubproto(name)
    push!(SUBProtocols, string(name))
    return true
end






"""
`target(request) => String`

Convenience function for reading upgrade request target.
    E.g.
```julia
    function gatekeeper(req, ws)
        if target(req) == "/gamepad"
            @spawnat 2 gamepad(ws)
        elseif target(req) == "/console"
            @spawnat 3 console(ws)
            ...
        end
    end
```
Then, in browser javascript (or equivalent with Julia WebSockets.open( , ))
```javascript
function load(){
    var wsuri = document.URL.replace("http:", "ws:");
    ws1 = new WebSocket(wsuri + "/gamepad");
    ws2 = new WebSocket(wsuri + "/console");
    ws3 = new WebSocket(wsuri + "/graphics");
    ws4 = new WebSocket(wsuri + "/audiochat");
    ws1.onmessage = function(e){vibrate(e.data)}
    } // load

```
"""
function target   # Methods added in include files
end

"""
`subprotocol(request) => String`

Convenience function for reading upgrade request subprotocol.
Acceptable subprotocols need to be predefined using
addsubproto(myprotocol). No other subprotocols will pass the handshake.
E.g.
```julia
WebSockets.addsubproto("instructions")
WebSockets.addsubproto("relay_backend")
function gatekeeper(req, ws)
    subpr = WebSockets.subprotocol(req)
    if subpr == "instructions"
        instructions(ws)
    elseif subpr == "relay_backend"
        relay_backend(ws)
    end
end
```

Then, in browser javascript (or equivalent with Julia WebSockets.open( , ))
```javascript
function load(){
    var wsuri = document.URL.replace("http:", "ws:");
    ws1 = new WebSocket(wsuri, "instructions");
    ws2 = new WebSocket(wsuri, "relay_backend");
    ws1.onmessage = function(e){doinstructions(e.data)};
    ...
    } // load
```
"""
function subprotocol # Methods added in include files
end


"""
`origin(request) => String`
Convenience function for checking which server / port address
the client claims its code was downloaded from.
The resource path can be found with target(req).
E.g.
```julia
function gatekeeper(req, ws)
    orig = WebSockets.origin(req)
        if startswith(orig, "http://localhost") || startswith(orig, "http://127.0.0.1")
        handlewebsocket(ws)
    end
end
```
"""
function origin # Methods added in include files
end


"""
`writeguarded(websocket, message) => Bool`

Return true if write is successful, false if not.
The peer can potentially disconnect at any time, but no matter the 
cause you will usually just want to exit your websocket handling function
when you can't write to it.
    
"""
function writeguarded(ws, msg)
    try
        write(ws, msg)
    catch 
        return false
    end
    true
end

"""
`readguarded(websocket) => (Vector, Bool)`

Return (data::Vector, true)
        or
        (Vector{UInt8}(), false)

The peer can potentially disconnect at any time, but no matter the 
cause you will usually just want to exit your websocket handling function
when you can't write to it.

E.g.
```julia
while true
    data, success = readguarded(websocket)
    !success && break
    println(String(data))
end
```
"""
function readguarded(ws)
    data = Vector{UInt8}()
    success = true
    try
        data = read(ws)
    catch err
        data = Vector{UInt8}()
        success = false
    finally
        return data, success
    end
end


@require HTTP include("HTTP.jl")
@require HttpServer include("HttpServer.jl")
end # module WebSockets
