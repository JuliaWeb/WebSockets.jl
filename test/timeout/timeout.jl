# Provided that three browser types are found, 
# this opens 9 webscokets * (3 browsers + 1 Julia ) = 36 websockets.
# They close from the client side after
# timeouts up to 256 seconds.
# Not included in runtests.jl.
# Checking against errors equires inspecting REPL.

using Test
using WebSockets
import Dates.now
include("../../benchmark/functions_open_browsers.jl")
include("timeout_functions.jl")

const WSIDLIST = Dict{typeof(time_ns()) , String}()
const WSLIST = Dict{typeof(time_ns()) , WebSocket}()
const CLIENTTASKS = Dict{typeof(time_ns()) , Task}()
const CLOSINGMESSAGES = Dict{typeof(time_ns()) , String}()
const CURRENT = Vector{Pair{WebSocket, String}}()
const T0 = now()

const SERVER = WebSockets.ServerWS(handle, gatekeeper, rate_limit = 1000//1)
const OLDLOGGER = WebSockets.global_logger()

WebSockets.global_logger(WebSocketLogger())
# Uncomment to include logging messages from HTTP
#WebSockets.global_logger(WebSocketLogger(shouldlog= (_, _, _, _, _) -> true))

const SERTASK = @async WebSockets.serve(SERVER, 8000)

open_a_browser()

# We'll also open a second and third type of browser. The default sequence is
# ["chrome", "firefox", "iexplore", "safari", "phantomjs"]. If one is unavailable,
# the next will be picked.
open_a_browser()
open_a_browser()

# The browsers are working on opening client side websockets. Meanwhile,
# Julia will open some, too:
for i = 0:8
    sec = 2^i
    wsh = clientwsh(sec)
    push!(CLIENTTASKS, time_ns() => @async WebSockets.open(wsh, "ws://127.0.0.1:8000"))
    # We want to yield for asyncronous functions started by incoming
    # requests from browsers. Otherwise, the browsers could perhaps become bored.
    yield()
end

# The time to open a websocket may depend on things like the browser updating,
# or, for Julia, if compilation is necessary.
sleep(24)
if checktasks() == 9
    @wslog "All client tasks are running or finished without error"
else
    @warn CLIENTTASKS
end
@test length(WSLIST) == 36
for (key, ws) in WSLIST
    push!(CURRENT, ws => get(WSIDLIST, key, "See WSIDLIST directly"))
end
@wslog CURRENT
@async begin
    # Wait for all timeouts (the longest is 256s)
    @wslog "\e[32m --- The final tests will run in 256s + 58s = ---\n
    \t For more viewing pleasure, now inspect CURRENT\n
    \t\e[39m or alternatively WSIDLIST WSLIST  CLIENTTASKS  CLOSINGMESSAGES and SERVER"
    sleep(314)
    #put!(SERVER.in("Job well done!"))
    for (key, ws) in WSLIST
        @wslog ws, WSIDLIST[key]
        @test !WebSockets.isopen(ws)
    end

    close(SERVER)

    #Check that all the sockets were closed for the right reason
    for clmsg in values(CLOSINGMESSAGES)
        @test occursin("seconds are up", clmsg)
    end
    WebSockets.global_logger(OLDLOGGER)
end
nothing