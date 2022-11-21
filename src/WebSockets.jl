"""
    WebSockets
This module implements the WebSockets protocol. It relies on the package HTTP.jl.

Websocket|server relies on a client initiating the connection.
Websocket|client initiate the connection.

The client side of the connection is most typically a browser with
scripts enabled. Browsers are always the initiating, client side. But the
peer can be any program, in any language, that follows the protocol. That
includes another Julia session, running in a parallel process or task.

    Future improvements:
1. Check rsv1 to rsv3 values. This will reduce bandwidth.
2. Optimize maskswitch!, possibly threaded above a certain limit.
3. Split messages over several frames.
"""
module WebSockets
using Dates
using Logging
import Sockets
import Sockets: TCPSocket,        # For locked_write, show
                IPAddr,           # For serve
                InetAddr          # For serve
import Base64:  base64decode,     # For generate_websocket_key
                base64encode      # For open client websocket
import Base:    IOServer,         # For serve
                ReinterpretArray, # For data type
                buffer_writes,    # For init_socket
                CodeUnits,        # For data type
                throwto           # For readframe_nonblocking
import HTTP                       # Depend on WebSockets.HTTP only
                                  # to avoid version conflicts!
import HTTP.Servers.MbedTLS       # For further imports
import HTTP.Servers.MbedTLS:
                MD_SHA1,          # For generate_websocket_key
                digest            # For generate_websocket_key

# further imports from HTTP in this file
include("HTTP.jl")

# A logger based on ConsoleLogger. This has an effect
# only if the user chooses to use WebSocketLogger.
include("Logger/websocketlogger.jl")

export WebSocket,
       serve,
       readguarded,
       writeguarded,
       write,
       read,
       close,
       subprotocol,
       target,
       send_ping,
       send_pong,
       WebSocketClosedError,
       addsubproto,
       WebSocketLogger,
       @wslog,
       Wslog

# revisit the need for defining this union type for method definitions. The functions would
# probably work just as fine with duck typing.
const Dt = Union{ReinterpretArray{UInt8,1,UInt16,Array{UInt16,1}},
            Vector{UInt8},
            CodeUnits{UInt8,String}   }
"A reasonable amount of time"
const TIMEOUT_CLOSEHANDSHAKE = 10.0

@enum ReadyState CONNECTED=0x1 CLOSING=0x2 CLOSED=0x3

""" Buffer writes to socket till flush (sock)"""
init_socket(sock) = buffer_writes(sock)


struct WebSocketClosedError <: Exception
    message::String
end

struct WebSocketError <: Exception
    status::Int16
    message::String
end

"Status codes according to RFC 6455 7.4.1"
const codeDesc = Dict{Int, String}(
    1000=>"Normal",                     1001=>"Going Away",
    1002=>"Protocol Error",             1003=>"Unsupported Data",
    1004=>"Reserved",                   1005=>"No Status Recvd- reserved",
    1006=>"Abnormal Closure- reserved", 1007=>"Invalid frame payload data",
    1008=>"Policy Violation",           1009=>"Message too big",
    1010=>"Missing Extension",          1011=>"Internal Error",
    1012=>"Service Restart",            1013=>"Try Again Later",
    1014=>"Bad Gateway",                1015=>"TLS Handshake")

"""
A WebSocket is a wrapper over a TCPSocket. It takes care of wrapping outgoing
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
   addsubproto("json")
```
Also see function subprotocol
"""
const SUBProtocols= Array{String,1}()

"""
    write_fragment(io, islast, opcode, hasmask, data::Array{UInt8})
Write the raw frame to a bufffer. Websocket|client must set 'hasmask'.
"""
function write_fragment(io::IO, islast::Bool, opcode, hasmask::Bool, data::Dt)
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
            # Avoid masking Strings bytes in place.
            # This makes client websockets slower than server websockets.
            data = copy(data)
        end
        # Write the random masking key to io, also mask the data in-place
        write(io, maskswitch!(data))
    end
    write(io, data)
end

""" Write without interruptions"""
function locked_write(io::IO, islast::Bool, opcode, hasmask::Bool, data::Dt)
    isa(io, TCPSocket) && lock(io.lock)
    try
        write_fragment(io, islast, opcode, hasmask, data)
    finally
        if isa(io, TCPSocket)
            flush(io)
            unlock(io.lock)
        end
    end
end

""" Write text data; will be sent as one frame."""
function Base.write(ws::WebSocket,data::String)
    # add a method for reinterpreted strings as well? See const Dt.
  #  locked_write(ws.socket, true, OPCODE_TEXT, !ws.server, Vector{UInt8}(data)) # Vector{UInt8}(String) will give a warning in v0.7.
  locked_write(ws.socket, true, OPCODE_TEXT, !ws.server, codeunits(data)) # Vector{UInt8}(String) will give a warning in v0.7.
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
    close(ws::WebSocket, statusnumber = n)
    close(ws::WebSocket, statusnumber = n, freereason = "my reason")
Send an OPCODE_CLOSE frame, and wait for the same response or until
a reasonable amount of time, $(round(TIMEOUT_CLOSEHANDSHAKE, digits=1)) s, has passed.
Data received while closing is dropped.
Status number n according to RFC 6455 7.4.1 can be included, see WebSockets.codeDesc
"""
function Base.close(ws::WebSocket; statusnumber = 0, freereason = "")
    if isopen(ws)
        ws.state = CLOSING
        if statusnumber == 0
            locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, UInt8[])
        elseif freereason == ""
            statuscode = reinterpret(UInt8, [hton(UInt16(statusnumber))])
            locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, copy(statuscode))
        else
            statuscode = vcat(reinterpret(UInt8, [hton(UInt16(statusnumber))]),
                                Vector{UInt8}(freereason))
            locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, copy(statuscode))
        end

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
            # Unknown errors are rethrown.
            errtyp = typeof(err)
            errtyp != InterruptException &&
                errtyp != Base.IOError &&
                errtyp != HTTP.IOExtras.IOError &&
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
    rsv1::Bool     # Set for compressed messages.
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
        ws.state = CLOSED
        try
            locked_write(ws.socket, true, OPCODE_CLOSE, !ws.server, UInt8[])
        catch e
        end
        # Find out why the other side wanted to close.
        # RFC 6455 5.5.1. If there is a status code, it's a two-byte number in network order.
        if wsf.payload_len == 0
            reason = " No reason "
        elseif wsf.payload_len == 2
            scode = Int(reinterpret(UInt16, reverse(wsf.data))[1])
            reason = string(scode) * ": " * get(codeDesc, scode, "")
        else
            scode = Int(reinterpret(UInt16, reverse(wsf.data[1:2]))[1])
            reason = string(scode) * ": " * String(wsf.data[3:end])
        end
        throw(WebSocketClosedError("ws|$(ws.server ? "server" : "client") respond to OPCODE_CLOSE " * reason))
    elseif wsf.opcode == OPCODE_PING
        @debug ws, " received OPCODE_PING"
        send_pong(ws, wsf.data)
    elseif wsf.opcode == OPCODE_PONG
        @debug ws, " received OPCODE_PING"
        # Nothing to do here; no reply is needed for a pong message.
    else  # %xB-F are reserved for further control frames
        error("while handle_control_frame(ws|$(ws.server ? "server" : "client"), wsf): Unknown opcode $(wsf.opcode)")
    end
end

""" Read a frame: turn bytes from the websocket into a WebSocketFragment."""
function read_frame(ws::WebSocket)
    # Try to read two bytes. There is no guarantee that two bytes are actually allocated.
    ab = Array{UInt8}(undef, 2)
    if readbytes!(ws.socket, ab) != 2
      throw(WebSocketError(1006, "Client side closed socket connection"))
    end

    #=
    Browsers will seldom close in the middle of writing to a socket,
    but other clients often do, and the stacktraces can be very long.
    ab can be assigned, but of length 1. Use an enclosing try..catch in the calling function
    =#
    a = ab[1]
    fin    = (a & 0b1000_0000) >>> 7  # If fin, then is final fragment
    rsv1   = a & 0b0100_0000  # If not 0, fail.
    rsv2   = a & 0b0010_0000  # If not 0, fail.
    rsv3   = a & 0b0001_0000  # If not 0, fail.
    opcode = a & 0b0000_1111  # If not known code, fail.

    b = ab[2]
    mask = (b & 0b1000_0000) >>> 7
    hasmask = mask != 0

    if hasmask != ws.server
        if ws.server
            msg = "WebSocket|server cannot handle incoming messages without mask. Ref. rcf6455 5.3"
        else
            msg = "WebSocket|client cannot handle incoming messages with mask. Ref. rcf6455 5.3"
        end
        throw(WebSocketError(1002, msg))
    end

    payload_len::UInt64 = b & 0b0111_1111
    if payload_len == 126
        payload_len = ntoh(read(ws.socket, UInt16))  # 2 bytes
    elseif payload_len == 127
        payload_len = ntoh(read(ws.socket, UInt64))  # 8 bytes
    end

    maskkey = hasmask ? read(ws.socket, 4) : UInt8[]

    data = read(ws.socket,Int(payload_len))
    hasmask && maskswitch!(data, maskkey)

    return WebSocketFragment(
        fin, rsv1, rsv2, rsv3,
        opcode, mask, payload_len, maskkey, data
    )
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
           return read(ws)
        end

        # Handle data message that uses multiple fragments.
        if !frame.is_last
            return vcat(frame.data, read(ws))
        end
        return frame.data
    catch err
        try
            server_str = ws.server ? "server" : "client"
            if err isa InterruptException
                msg = "while read(ws|$(server_str) received InterruptException."
                # This exception originates from this side. Follow close protocol so as not to irritate the other side.
                close(ws, statusnumber = 1006, freereason = msg)
                throw(WebSocketClosedError(msg * " Performed closing handshake."))
            elseif err isa WebSocketError
                # This exception originates on the other side. Follow close protocol with reason.
                close(ws, statusnumber = err.status)
                throw(WebSocketClosedError("while read(ws|$(server_str)) $(err.message) - Performed closing handshake."))
            elseif err isa Base.IOError || err isa Base.EOFError
                throw(WebSocketClosedError("while read(ws|$(server_str)) $(string(err))"))
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
    return UInt8[]
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
    rt = @async _readinterruptable(chnl)
    bind(chnl, rt)
    yield()
    # Define a task for throwing interrupt exception to the (possibly blocked) read task.
    # We don't start this task because it would never return
    killta = @task try
        throwto(rt, InterruptException())
    catch
    end
    # We start the killing task. When it is scheduled the second time,
    # we pass an InterruptException through the scheduler.
    try
        schedule(killta, InterruptException(), error = false)
    catch
    end
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

"""
    maskswitch!(data)
    maskswitch!(data, key:: 4-element Vector{UInt8})

Masks or unmasks data in-place, returns the key used.
Calling twice with the same key restores data.
Ref. RFC 6455 5-3.
"""
function maskswitch!(data, mask = rand(UInt8, 4))
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

To check the errors (if you get any), temporarily set loging min_level to Logging.debug, e.g:

```julia
using WebSockets, Logging
global_logger(WebSocketLogger(stderr, Logging.Debug));
```
"""
function writeguarded(ws, msg)
    try
        write(ws, msg)
    catch err
        @debug err
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

To check the errors (if you get any), temporarily set loging min_level to Logging.debug, e.g:

```julia
using WebSockets, Logging
global_logger(WebSocketLogger(stderr, Logging.Debug));
```

"""
function readguarded(ws)
    data = Vector{UInt8}()
    success = true
    try
        data = read(ws)
    catch err
        @debug err
        data = Vector{UInt8}()
        success = false
    finally
        return data, success
    end
end

# import Base.show and add methods in this file
include("show_ws.jl")
end # module WebSockets
