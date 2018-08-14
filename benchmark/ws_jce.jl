__precompile__(false)
"""
Submodule Julia Client Echo
Intended for running in its own worker process.
HTTP and WebSockets need to be loaded in the calling context.
LOAD_PATH must include the directory logutils_ws.
See comment at the end of this file for debugging code.
"""
module ws_jce
using ..HTTP
using ..WebSockets
# We want to log to a separate file, and so use our own
# instance of logutils_ws in this process
import logutils_ws: logto, clog, zlog, zflush, clog_notime
const SRCPATH = Base.source_dir() == nothing ? Pkg.dir("WebSockets", "benchmark") : Base.source_dir()
const LOGFILE = "ws_jce.log"

const PORT = 8000
const SERVER = "ws://127.0.0.1:$(PORT)"
const CLOSEAFTER = Base.Dates.Second(30)

"""
Opens a client, echoes with an optional delay, an integer in milliseconds.
Stores time records for received messages and before sending messages.
Specify the delay in milliseconds by sending a message on the websocket:
    send(ws_jce, "delay|15")
Echoes any message except "exit" and "delay".

Delays to reading, in the websocket use situation, would be caused by usefully spent
calculation time between reads. However, they may be interpreted by the underlying protocol
as transmission problems and cause large slowdowns. Hence the interest in testing
with delays. A countermeasure for optimizing speed might be to run a websocket
reading function in a parallel, not asyncronous process, putting messages on an internal queue.

At exit or after CLOSEAFTER, this function sends one message containing two vectors of
timestamps [ns].
"""
function echowithdelay_jce()
    # This will be run in a worker process. Even so, individual console log
    # output will be redirected to process 1 and prefixed
    # with a "From worker 2".
    # It will also be interspersed with process 1 output,
    # sometimes before a line is finished printing.
    # We use :green to distinguish more easily.
    id = "echowithdelay_jce"
    f = open(joinpath(SRCPATH, "logs", LOGFILE), "w")
    try
        logto(f)
        clog(id, :green, "Open client on ", SERVER, "\nclient side handler ", _jce)
        zflush()
        WebSockets.open(_jce, SERVER)
        zlog(id, :green, " Websocket closed, control returned.")
    catch err
        clog(id, :red, err)
        clog_notime.(stacktrace(catch_backtrace())[1:4])
        zflush()
    finally
        clog(id, :green, " Closing log ", LOGFILE)
        zflush()
        logto(Base.DevNullStream())
        close(f)
    end
end
"
Handler for client websocket, defined by echowithdelay_jce
"
function _jce(ws)
    id = "_jce"
    clog(id, :green, ws)
    zflush()
    receivetimes = Vector{Int64}()
    replytime = Int64(0)
    replytimes = Vector{Int64}()
    msg = Vector{UInt8}()
    delay = 0 # Integer milliseconds
    t1 = now() + CLOSEAFTER
    while isopen(ws) && now() < t1
        # read, record receive time
        msg = read(ws)
        ti = time_ns()
        push!(receivetimes, Int64(ti < typemax(Int64) ? ti : 0 ))
        # break out when receiving 'exit'
        length(msg) == 4 && msg == Vector{UInt8}("exit") && break
        # react to delay instruction
        if length(msg) < 16 && msg[1:6] == Vector{UInt8}("delay=")
            delay = Meta.parse(Int, String(msg[7:end]))
            clog(id, :green, " Changing delay to ", delay, " ms")
            zflush()
        end
        sleep(delay / 1000)
        # record send time, echo
        replytime = time_ns()
        write(ws, msg)
        # clean record of instruction message
        if length(msg) > 16 && msg[1:6] != Vector{UInt8}("delay=")
            push!(replytimes, Int64(replytime < typemax(Int64) ? replytime : 0 ))
        elseif msg[1:6] != Vector{UInt8}("delay=")
            push!(replytimes,  Int64(replytime < typemax(Int64) ? replytime : 0 ))
        end
    end
    if length(receivetimes) > 1
        # Don't include receive time for the "exit" message. Reply time was not recorded
        pop!(receivetimes)
        if length(receivetimes) > 1
            # Send one message with serialized receive and reply times.
            buf = IOBuffer()
            serialize(buf, (receivetimes, replytimes))
            if isopen(ws)
                write(ws, take!(buf))
                zlog(id, :green, " Sent serialized receive and reply times.")
                zflush()
            end
        end
    end
    clog(id, :green, " Exit, close websocket.")
    zflush()
    # Exiting this function starts a closing handshake
    nothing
end
end # module

#=
For debugging in a separate terminal:

using WebSockets
const SRCPATH = Base.source_dir() == nothing ? Pkg.dir("WebSockets", "benchmark") :Base.source_dir()
const LOGGINGPATH = realpath(joinpath(SRCPATH, "../logutils/"))
# for finding local modules
SRCPATH ∉ LOAD_PATH && push!(LOAD_PATH, SRCPATH)
LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)

import ws_jce.echowithdelay_jce
ws_jce.echowithdelay_jce()
=#