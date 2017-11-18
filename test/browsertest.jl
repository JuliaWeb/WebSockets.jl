# Included in runtests at the end.
# Can also be run directly.
# Launches available browsers on browsertest.html.
# Websockets are intiated by the browser / web page. 
# Handler_functions_websockets respond and store allocations & etc.
# After a successfull exchange, the browsers navigate to a second html page
# for binary performance tests. In the end, all websockets are closed
# and a summary is output.

cd(Pkg.dir("WebSockets","test"))
using Compat
using WebSockets
using Base.Test
const WEBSOCKETS = Dict{Int, WebSockets.WebSocket}()
const RECEIVED_WS_MSGS_TIME = Dict{Int, Vector{Float64}}()
const RECEIVED_WS_MSGS_ALLOCATED = Dict{Int, Vector{Int64}}()
const RECEIVED_WS_MSGS_LENGTH = Dict{Int, Vector{Int64}}()
const WEBSOCKETS_SUBPROTOCOL = Dict{Int, WebSockets.WebSocket}()
const WEBSOCKETS_BINARY = Dict{Int, WebSockets.WebSocket}()
# Note that only text messages are stored. Binary messages are discarded.
const RECEIVED_WS_MSGS = Dict{Int, Vector{String}}()

# Logs from travis indicate it takes 7 s to fire up Safari and
# have the first websocket open. This can easily increase if more
# browsers become available.
const FIRSTWAIT = Base.Dates.Second(2)
const MAXWAIT = Base.Dates.Second(60*15)
global n_responders = 0
include("functions_server.jl")
closeall()
server = start_ws_server_async()
include("functions_open_browsers.jl")
info("This OS is $(string(Sys.KERNEL))\n")
n_browsers = 0
#n_browsers += open_testpage("firefox")
n_browsers += open_all_browsers()

# Control flow passes to async handler functions

if n_browsers > 0
    info("Sleeping main thread for an initial minimum of $FIRSTWAIT\n")
    t0 = now()
    while now()-t0 < FIRSTWAIT
        sleep(1)
    end
    contwait = true
    while contwait && now()-t0 < MAXWAIT
        # All websockets close briefly when navigating from browsertest.html to browsertest2.html
        # So we require two consecutive checks for websockets before exiting, with 2 seconds between.
        contwait = count_open_websockets() > 0
        if !contwait
            sleep(2)
            passedtime = now() - t0
            exitlatestin = MAXWAIT + t0- now()
            info("$(div(passedtime.value, 1000)) s passed. Max remaining test time $(div(exitlatestin.value, 1000)) s\n")
        end
        sleep(.5)
        contwait = contwait && count_open_websockets() > 0
    end
end
n_opensockets = count_open_websockets()

closeall()
info(Dates.format(now(), "HH:MM:SS"), "\tClosed web sockets and servers.")
# sum up
allocs = Vector{Int64}()
times = Vector{Float64}()
lengths = Vector{Int64}()
n_msgs = 0
n_text = 0
n_ws = 0
for ke in keys(WEBSOCKETS)
    n_ws += 1
    for msgno = 1:length(RECEIVED_WS_MSGS_LENGTH[ke])
        if RECEIVED_WS_MSGS_LENGTH[ke][msgno] > 0
            n_msgs += 1
            push!(allocs, RECEIVED_WS_MSGS_ALLOCATED[ke][msgno])
            push!(times, RECEIVED_WS_MSGS_TIME[ke][msgno])
            push!(lengths, RECEIVED_WS_MSGS_LENGTH[ke][msgno])
            if haskey(RECEIVED_WS_MSGS, ke)
                n_text += 1
            end
        end
    end
end
n_binary = n_msgs - n_text

# print summary
info("Spawned $n_browsers browsers. $n_browsers made requests. Opened $n_ws sockets, $n_opensockets did not close as intended.")
info("Received $n_msgs messages, $n_text text and $n_binary binary, $(round(sum(lengths)/ 1000 / 1000,3)) Mb, sent a similar amount.")





if n_msgs > 0
    maxlength = maximum( lengths )
    minlength = minimum( va -> va > 0.0 ? va:typemax(va), lengths )
    avglength = sum(lengths) / n_msgs

    maxaloc = maximum(  va -> va < Inf ? va:0.0, allocs ./ lengths )
    minaloc = minimum( va -> va > 0.0 ? va:typemax(va), allocs ./ lengths )
    avgaloc = sum(allocs) / sum(lengths)

    maxtime = maximum(va -> va < Inf ? va:0.0, times)
    mintime = minimum(va -> va > 0.0 ? va:typemax(va), times)
    avgtime = sum(times) / n_msgs

    maxspeed = maximum(va -> va < Inf ? va:0.0, lengths ./ times)
    minspeed = minimum(va -> va > 0.0 ? va:typemax(va), lengths ./ times)
    avgspeed = sum(lengths) / sum(times)

    info("Length of messages received\n",
        "\t\tAverage length:\t\t", round(avglength / 1000, 3), " kB\n",
        "\t\t\Minimum :\t\t", minlength , " b\n",
        "\t\t\Maximum :\t\t", round(maxlength / 1000 / 1000 , 3), " Mb\n")

    info("Time spent reading and waiting for received messages\n",
        "\t\tAverage time:\t\t", round(avgtime, 4), " s\n",
        "\t\t\Minimum :\t\t", mintime , " s\n",
        "\t\t\Maximum :\t\t", maxtime, " s\n")

    info("Reading speed (strongly affected by the active browsers)\n",
        "\t\tAverage speed:\t", round(avgspeed / 1000 / 1000, 3), " Mb/s\n",
        "\t\t\Minimum :\t", round(minspeed / 1000 / 1000 , 10), " Mb/s\n",
        "\t\t\Maximum :\t", round(maxspeed / 1000 / 1000, 3), " Mb/s\n")

    info("Allocations for reading, bytes allocated per byte received\n",
        "\t\tAverage allocation:\t", round(avgaloc, 3), "\n",
        "\t\t\Minimum :\t\t", round(minaloc, 3), "\n",
        "\t\t\Maximum :\t\t", round(maxaloc, 3), "\n",)

    info("Text messages received per websocket:")
    for m in RECEIVED_WS_MSGS
        display(m)
    end

else
    info("Failure on speed / allocation test.")
end

@test n_opensockets == 0
@test n_msgs == n_responders * 37