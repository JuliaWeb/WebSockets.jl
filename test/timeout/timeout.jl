# This opens 14*3 = 42 websockets which close from the client side after
# timeouts up to 8192 seconds.
# Not included in runtests.jl because this takes two and a half hours to run.
# Checking against erros equires inspecting REPL.

using Test
using WebSockets
import Dates.now
include("../../benchmark/functions_open_browsers.jl")
include("timeout_functions.jl")

const WSIDLIST = Vector{String}()
const WSLIST = Vector{WebSocket}()
const CLIENTTASKS = Vector{Task}()
const CLOSINGMESSAGES = Vector{String}()

const T0 = now()
# At Http 0.7 / WebSockets 1.3, there is no obviously nice interface to limiting
# the maximum simulconnection pool. We settle for a naughty as well as ugly way, and state our
# intention to fix this up (sometime). It should not concern timeouts, just
# our ability to open many sockets at a time.
@eval WebSockets.HTTP.ConnectionPool default_connection_limit = 32
# The default ratelimit is below the number of websockets we're intending to open.
const SERVER = WebSockets.ServerWS(handle, gatekeeper, ratelimit = 0//1)
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
    push!(CLIENTTASKS, @async WebSockets.open(wsh, "ws://127.0.0.1:8000"))
    # We want to yield for asyncronous functions started by incoming
    # requests from browsers. Otherwise, the browsers could perhaps become bored.
    yield()
end

function checktasks()
    count = 0
    for clita in CLIENTTASKS
        count +=1
        if clita.state == :failed
            @error "Client websocket task ", count, " failed"
        end
    end
    count
end

# The time to open a websocket may depend on things like the browser updating,
# or, for Julia, if compilation is necessary.
sleep(24)
if checktasks() == 14
    @wslog "All client tasks are running without error"
end
@test length(WSLIST) == 42
# Wait for all timeouts (the longest is 8192s)
sleep(8250)
put!(SERVER.in("Job well done!"))
for (ws, wsid) in zip(WSLIST, WSIDLIST)
    @wslog ws, " ", wsid
    @test !WebSockets.isopen(ws)
end

# Check that all the sockets were closed for the right reason
function checkreasons()
    for clmsg in CLOSINGMESSAGES
        @test occursin("seconds are up", clmsg)
    end
end
checkreasons()
WebSockets.global_logger(OLDLOGGER)
nothing
