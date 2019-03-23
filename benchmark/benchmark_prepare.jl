# See benchmark.jl for definitions

# This file collects data and tests functions.
# The intention is preparing input for a benchmark suite,
# but the output from this file actually is sufficient for some purposes.
#
# Both log file, results plots and tables are printed to the same file.
# Viewing the plots in a text editor is probably possible, see UnicodePlots.jl.
# Pull request welcome if someone can figure out how to do it.
# Running this file on a Windows laptop with all browsers takes 5-10 minutes.

if !@isdefined LOGGINGPATH
    (@__DIR__) ∉ LOAD_PATH && push!(LOAD_PATH, @__DIR__)
    const LOGGINGPATH = realpath(joinpath(@__DIR__, "..", "logutils"))
    LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)
end

include("functions_open_browsers.jl")
include("functions_benchmark.jl")

"A vector of message sizes"
const VSIZE = reverse([i^3 * 1020 for i = 1:12])

#
prepareworker()
# Load modules on both processes
using WebSockets
import WebSockets.HTTP
using ws_jce
import UnicodePlots: lineplot
using Dates
using Random
using Serialization
import Millboard.table
import ws_hts: listen_hts,
               getws_hts,
               close_hts
import WebSockets.global_logger

#
# TODO use a more direct function, not a macro
#remotecall_fetch(ws_jce.@debug, 2, "ws_jce ", :green, " is ready")

# Start async HTS server on this process and check that it is up and running
const TIMEOUT = Second(20)
hts_task = start_hts(TIMEOUT)

"""
Prepare logging for this process

    logs are written to console as well as to a file, which
    is different for the other process.
    Logs in other processes appear in console with a delay, hence the timestamp
    is interesting.
    To write log file buffer to disk immediately, call zflush().
    To drop duplicate console log, use zlog(..) instead of @debug(..)
"""
const ID = "Benchmark"
const LOGFILE = "benchmark_prepare.log"
global fbm = open(joinpath(@__DIR__, "logs", LOGFILE), "w")
logto(fbm)
@debug(ID, "Started async HTS and prepared parallel worker")
zflush()


#
#  Do an initial test run, HTS-JCE, brief text output
#

const INITSIZE = 130560
const INITN = 200


# Measured time interval vectors [ns]
# Time measurements are taken directly both at server and client
global testid, serverlatencies, clientlatencies = HTS_JCE(INITN, INITSIZE)
# Calculate speeds [ns/b] and averaged speeds (bandwidths)
global serverspeeds, clientspeeds,
    serverbandwidth, clientbandwidth = serverandclientspeeds(INITSIZE, serverlatencies, clientlatencies)
# Store plots and a table in dictionaries
global vars= [:serverspeeds, :clientspeeds]
global init_plots = Dict(testid => lp(vars, testid));
global init_tables = Dict(testid => tabulate(vars));
global init_serverbandwidths = Dict(testid => serverbandwidth);
global init_clientbandwidths = Dict(testid => clientbandwidth);
# Sleep to avoid interspersing with worker output to REPL
sleep(2)
# Brief output to file and console
@debug(testid, " Initial test run with messagesize ", INITSIZE, " bytes \n\t",
    "serverbandwidth = ", :yellow,  round(serverbandwidth, digits=4), :normal, " [ns/b] = [s/GB]\n\t",
    :normal, "clientbandwidth = ", :yellow, round(clientbandwidth, digits=4), :normal, " [ns/b] = [s/GB]")

#
#  Continue initial test run with HTS-BCE, brief text output for each browser
#

COUNTBROWSER.value = 0
global serverbandwidth = 0.
global clientbandwidth = 0.
global serverbandwidths = Vector{Float64}()
global clientbandwidths = Vector{Float64}()
global t1 = Vector{Int}()
global t2 = Vector{Int}()
global t3 = Vector{Int}()
global t4 = Vector{Int}()
global browser = ""
global alright = true
while alright
    # Measured time interval vectors [ns] for the next browser in line
    # Time measurements are taken only at server; a message pattern
    # is used to distinguish server and client performance
    global browser, t1, t2, t3, t4 = HTS_BCE(INITN, INITSIZE)
    if browser != ""
        # Calculate speeds [ns/b] and averaged speeds (bandwidths)
        serverspeeds, clientspeeds,
            serverbandwidth, clientbandwidth =
            serverandclientspeeds_indirect(INITSIZE, t1, t2, t3, t4)
        # Store plots and a table in dictionaries
        testid = "HTS_BCE " * browser
        push!(init_plots, testid => lp(vars, testid));
        #push!(init_tables, testid => table(eval.(vars)..., names = vars));
        push!(init_tables, testid => tabulate(vars));

        push!(init_serverbandwidths, testid => serverbandwidth);
        push!(init_clientbandwidths, testid => clientbandwidth);
        # Brief output to file and console
        @debug(testid, " Initial test run with messagesize ", INITSIZE, " bytes \n\t",
            "serverbandwidth = ", :yellow,  round(serverbandwidth, digits=4), :normal, " [ns/b] = [s/GB]\n\t",
            :normal, "clientbandwidth = ", :yellow, round(clientbandwidth, digits=4), :normal, " [ns/b] = [s/GB]")
    else
        alright = false
    end
end

#
#  Collect HTS_JCE bandwidths vs message size
#

const SAMPLES = 200
serverbandwidths = Dict{String, Vector{Float64}}()
clientbandwidths = Dict{String, Vector{Float64}}()
for msgsiz in VSIZE
    # Measured time interval vectors [ns]
    # Time measurements are taken directly both at server and client
    (testid, serverlatencies, clientlatencies) = HTS_JCE(SAMPLES, msgsiz)
    # Find averaged speed (bandwidth) scalars
    (_, _,
        sbw, cbw) = serverandclientspeeds(msgsiz, serverlatencies, clientlatencies)
    # Assign storage
    !haskey(serverbandwidths, testid) && push!(serverbandwidths, testid => Vector{Float64}())
    !haskey(clientbandwidths, testid) && push!(clientbandwidths, testid => Vector{Float64}())
    # Store bandwidths from this size
    push!(serverbandwidths[testid], sbw)
    push!(clientbandwidths[testid], cbw)
end

#
#  Collect HTS_BCE bandwidths
#  For individual and available browsers
#  This opens a lot of browser tabs; there may
#  be no easy way of closing them except
#  by closing Julia. internet explorer even
#  opens a separate window every time.
#
for msgsiz in VSIZE
    COUNTBROWSER.value = 0
    global t1 = Vector{Int}()
    global t2 = Vector{Int}()
    global t3 = Vector{Int}()
    global t4 = Vector{Int}()
    global browser = ""
    global alright = true
    while alright
        # Measured time interval vectors [ns] for the next browser in line
        # Time measurements are taken only at server; a message pattern
        # is used to distinguish server and client performance
        global browser, t1, t2, t3, t4 = HTS_BCE(SAMPLES, msgsiz)
        testid = "HTS_BCE " * browser
        if browser != ""
            # Find averaged speed (bandwidth) scalars
            (_, _,
                sbw, cbw) =
                    serverandclientspeeds_indirect(msgsiz, t1, t2, t3, t4)
            # Assign storage
            !haskey(serverbandwidths, testid) && push!(serverbandwidths, testid => Vector{Float64}())
            !haskey(clientbandwidths, testid) && push!(clientbandwidths, testid => Vector{Float64}())
            # Store bandwidths from this size
            push!(serverbandwidths[testid], sbw)
            push!(clientbandwidths[testid], cbw)
        else
            alright = false
        end
    end
end



#
#   Measurements are done. Close server and log file, open results log file.
#
close_hts()
@debug(ID, "Closing HTS server")
const RESULTFILE = "benchmark_results.log"
@debug(ID, "Results are summarized in ", joinpath(@__DIR__, "logs", RESULTFILE))
fbmr = open(joinpath(@__DIR__, "logs", RESULTFILE), "w")
logto(fbmr)
close(fbm)



#
# Find optimum message size and nominal 100% bandwidths
# Make and store plots and tables
#
global test_bestserverbandwidths = Dict{String, Float64}()
global test_bestclientbandwidths = Dict{String, Float64}()
global test_bestserverlatencies = Dict{String, Float64}()
global test_bestclientlatencies = Dict{String, Float64}()
global test_plots = Dict()
global test_tables = Dict()
global test_latency_plots = Dict()
global test_latency_tables = Dict()
global serverbandwidth = Vector{Float64}()
global clientbandwidth = Vector{Float64}()
global serverlatency = Vector{Float64}()
global clientlatency = Vector{Float64}()
global bestserverbandwidth = 0.
global bestclientbandwidth = 0.
global bestserverlatency = 0.
global bestclientlatency = 0.

for testid in keys(serverbandwidths)
    serverbandwidth = serverbandwidths[testid]
    clientbandwidth = clientbandwidths[testid]
    # Store the optimal bandwidths in a dictionary
    bestserverbandwidth = minimum(serverbandwidth)
    bestclientbandwidth = minimum(clientbandwidth)
    push!(test_bestserverbandwidths, testid => bestserverbandwidth);
    push!(test_bestclientbandwidths,  testid => bestclientbandwidth);
    # Store msgsiz-bandwidth line plots and tables in dictionaries
    vars = [:serverbandwidth, :clientbandwidth]
    tvars = vcat([:VSIZE], vars)
    push!(test_plots,  testid => lp([:VSIZE, :VSIZE], vars, testid));
    push!(test_tables,  testid => tabulate(tvars));

    # Store msgsiz-latency line plots and tables in dictionaries
    serverlatency = serverbandwidth .* VSIZE
    clientlatency = clientbandwidth .* VSIZE
    bestserverlatency = minimum(serverlatency)
    bestclientlatency = minimum(clientlatency)
    push!(test_bestserverlatencies,  testid => bestserverlatency);
    push!(test_bestclientlatencies,  testid => bestclientlatency);
    vars = [:serverlatency, :clientlatency]
    tvars = vcat([:VSIZE], vars)
    push!(test_latency_plots,  testid => lp([:VSIZE, :VSIZE], vars, testid));
    push!(test_latency_tables,  testid => tabulate(tvars));

    # Brief output to file and console






    @debug_notime(testid, :normal, " Varying message size: \n\t",
        "bestserverbandwidth = ", :yellow,  round(bestserverbandwidth, digits=4), :normal, " [ns/b] = [s/GB]",
        " @ size = ", VSIZE[firstmatch(serverbandwidth, bestserverbandwidth)], " b\n\t",
        :normal, "bestclientbandwidth = ", :yellow, round(bestclientbandwidth, digits=4), :normal, " [ns/b] = [s/GB]",
        " @ size = ", VSIZE[firstmatch(clientbandwidth, bestclientbandwidth)], " b\n\t",
        "bestserverlatency = ", :yellow,  Int(round(bestserverlatency)), :normal, " [ns] ",
        " @ size = ", VSIZE[firstmatch(serverlatency, bestserverlatency)], " b\n\t",
        :normal, "bestclientlatency = ", :yellow, Int(round(bestclientlatency)), :normal, " [ns]",
        " @ size = ", VSIZE[firstmatch(clientlatency, bestclientlatency)], " b\n\t"
        )
end


#
#   Full text output
#   The plots are not currently readably encoded in the text file
#

@debug_notime(ID, :bold, :yellow, " Plots of all samples :init_plots [ns/b], message size ", INITSIZE, " b ", SAMPLES, " samples" )
foreach(values(init_plots)) do pls
    foreach(values(pls)) do pl
        @debug_notime(pl)
    end
end
@debug_notime(ID, :bold, :yellow, " Tables of all samples, :init_tables, message size ", INITSIZE, " b ", SAMPLES, " samples" )
for (ke, ta) in  init_tables
    @debug_notime(ke, "\n=> ", ta, "\n")
end


@debug_notime(ID, :bold, :yellow, " Plots of varying size messages :test_plots [ns/b],\n\t VSIZE = ", VSIZE)
foreach(values(test_plots)) do pls
    foreach(values(pls)) do pl
        @debug_notime(pl)
    end
end

@debug_notime(ID, :bold, :yellow, " Tables of varying size messages :test_tables [ns/b]")
for (ke, ta) in  test_tables
    @debug_notime(ke, "\n=> ", ta, "\n")
end

@debug_notime(ID, :bold, :yellow, " Plots of varying size messages :test_latency_plots [ns],\n\t VSIZE = ", VSIZE)
foreach(values(test_latency_plots)) do pls
    foreach(values(pls)) do pl
        @debug_notime(pl)
    end
end

@debug_notime(ID, :bold, :yellow, " Tables of varying size messages :test_latency_tables [ns]")
for (ke, ta) in  test_latency_tables
    @debug_notime(ke, "\n=> ", ta, "\n")
end

@debug_notime(ID, :bold, :yellow, " Dictionary  :test_bestserverlatencies [ns]")
for (ke, va) in  test_bestserverlatencies
    @debug_notime(ke, " => \t", Int(round(va)))
end

@debug_notime(ID, :bold, :yellow, " Dictionary  :test_bestclientlatencies [ns]")
for (ke, va) in  test_bestclientlatencies
    @debug_notime(ke, " => \t", Int(round(va)))
end

@debug_notime(ID, :bold, :yellow, " Dictionary  :test_bestserverbandwidths [ns/b]")
for (ke, va) in  test_bestserverbandwidths
    @debug_notime(ke, " => \t", round(va, digits=4))
end

@debug_notime(ID, :bold, :yellow, " Dictionary  :test_bestclientbandwidths [ns/b]")
for (ke, va) in  test_bestclientbandwidths
    @debug_notime(ke, " => \t", round(va, digits=4))
end

zflush()
