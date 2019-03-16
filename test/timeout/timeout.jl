# This opens 14*3 = 42 websockets which close from the client side after
# timeouts up to 8192 seconds.
# Not included in runtests.jl because this takes two and a half hours to run.
# Checking against erros equires inspecting REPL.

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
# At Http 0.7 / WebSockets 1.3, there is no obviously nice interface to limiting
# the maximum simultaneous connections. We settle for a naughty as well as ugly way, and state our
# intention to fix this up (sometime). It should not concern timeouts, just
# our ability to open many sockets at a time.
@eval WebSockets.HTTP.ConnectionPool default_connection_limit = 32

const SERVER = WebSockets.ServerWS(handle, gatekeeper, rate_limit = 1000//1)
const OLDLOGGER = WebSockets.global_logger()

WebSockets.global_logger(WebSocketLogger())
# Uncomment to include logging messages from HTTP
#WebSockets.global_logger(WebSocketLogger(shouldlog= (_, _, _, _, _) -> true))

const SERTASK = @async WebSockets.serve(SERVER, 8000)
open_a_browser()
# We'll also open a second type of browser. If all are available, the default sequence is
# ["chrome", "firefox", "iexplore", "safari", "phantomjs"]
open_a_browser()

# The browsers are working on opening client side websockets. Meanwhile,
# Julia will open some, too:
for i = 0:13
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
if checktasks() == 14
    @wslog "All client tasks are running without error"
end
@test length(WSLIST) == 42
for (key, ws) in WSLIST
    push!(CURRENT, ws => get(WSIDLIST, key, "See WSIDLIST directly"))
end
@wslog CURRENT
@async begin
    # Wait for all timeouts (the longest is 8192s)
    @wslog "\e[32m --- The final tests will run in 8250s---\n
    \t For more viewing pleasure, now inspect CURRENT\n
    \t\e[39m or alternatively WSIDLIST WSLIST  CLIENTTASKS  CLOSINGMESSAGES and SERVER"
    sleep(8250)
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
