# See benchmark.jl for definitions

# This file collects data and tests functions.
# The intention is preparing input for a benchmark suite,
# but the output from this file actually is sufficient for some purposes.
#
# Both log file, results plots and tables are printed to the same file.
# Viewing the plots in a text editor is probably possible, see UnicodePlots.jl.
# Pull request welcome if someone can figure out how to do it.
# Running this file on a Windows laptop with all browsers takes 5-10 minutes.


if !isdefined(:SRCPATH)
    const SRCPATH = Base.source_dir() == nothing ? Pkg.dir("WebSockets", "benchmark") : Base.source_dir()
    const LOGGINGPATH = realpath(joinpath(SRCPATH, "../logutils/"))
    SRCPATH ∉ LOAD_PATH && push!(LOAD_PATH, SRCPATH)
    LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)
    include(joinpath(SRCPATH, "functions_open_browsers.jl"))
end


"A vector of message sizes"
const VSIZE = reverse([i^3 * 1020 for i = 1:12])
include(joinpath(SRCPATH, "functions_open_browsers.jl"))
include(joinpath(SRCPATH, "functions_benchmark.jl"))
#
prepareworker()
# Load modules on both processes
import HTTP
using WebSockets
using ws_jce
using UnicodePlots
import IndexedTables.table
import ws_hts: listen_hts, getws_hts
#
remotecall_fetch(ws_jce.clog, 2, "ws_jce ", :green, " is ready")
# Start async HTS server on this process and check that it is up and running
const TIMEOUT = Base.Dates.Second(20)
hts_task = start_hts(TIMEOUT)

"""
Prepare logging for this process

    logs are written to console as well as to a file, which
    is different for the other process.
    Logs in other processes appear in console with a delay, hence the timestamp
    is interesting.
    To write log file buffer to disk immediately, call zflush().
    To drop duplicate console log, use zlog(..) instead of clog(..)
"""
const ID = "Benchmark"
const LOGFILE = "benchmark_prepare.log"
import logutils_ws: logto, clog, zlog, zflush, clog_notime
fbm = open(joinpath(SRCPATH, "logs", LOGFILE), "w")
logto(fbm)
clog(ID, "Started async HTS and prepared parallel worker")
zflush()


#
#  Do an initial test run, HTS-JCE, brief text output
#

const INITSIZE = 130560
const INITN = 200

# Measured time interval vectors [ns]
# Time measurements are taken directly both at server and client
(testid, serverlatencies, clientlatencies) = HTS_JCE(INITN, INITSIZE)
# Calculate speeds [ns/b] and averaged speeds (bandwidths)
(serverspeeds, clientspeeds,
    serverbandwidth, clientbandwidth) = serverandclientspeeds(INITSIZE, serverlatencies, clientlatencies)
# Store plots and a table in dictionaries
vars= [:serverspeeds, :clientspeeds];
init_plots = Dict(testid => lp(vars, testid));
init_tables = Dict(testid => table(eval.(vars)..., names = vars));
init_serverbandwidths = Dict(testid => serverbandwidth);
init_clientbandwidths = Dict(testid => clientbandwidth);
# Sleep to avoid interspersing with worker output to REPL
sleep(2)
# Brief output to file and console
clog(testid, " Initial test run with messagesize ", INITSIZE, " bytes \n\t",
    "serverbandwidth = ", :yellow,  round(serverbandwidth, digits=4), :normal, " [ns/b] = [s/GB]\n\t",
    :normal, "clientbandwidth = ", :yellow, round(clientbandwidth, digits=4), :normal, " [ns/b] = [s/GB]")

#
#  Continue initial test run with HTS-BCE, brief text output for each browser
#

COUNTBROWSER.value = 0
serverbandwidth = 0.
clientbandwidth = 0.
serverbandwidths = Vector{Float64}()
clientbandwidths = Vector{Float64}()
t1 = Vector{Int}()
t2 = Vector{Int}()
t3 = Vector{Int}()
t4 = Vector{Int}()
browser = ""
success = true
while success
    # Measured time interval vectors [ns] for the next browser in line
    # Time measurements are taken only at server; a message pattern
    # is used to distinguish server and client performance
    (browser, t1, t2, t3, t4) = HTS_BCE(INITN, INITSIZE)
    if browser != ""
        # Calculate speeds [ns/b] and averaged speeds (bandwidths)
        (serverspeeds, clientspeeds,
            serverbandwidth, clientbandwidth) =
            serverandclientspeeds_indirect(INITSIZE, t1, t2, t3, t4)
        # Store plots and a table in dictionaries
        testid = "HTS_BCE " * browser
        push!(init_plots, testid => lp(vars, testid));
        push!(init_tables, testid => table(eval.(vars)..., names = vars));
        push!(init_serverbandwidths, testid => serverbandwidth);
        push!(init_clientbandwidths, testid => clientbandwidth);
        # Brief output to file and console
        clog(testid, " Initial test run with messagesize ", INITSIZE, " bytes \n\t",
            "serverbandwidth = ", :yellow,  round(serverbandwidth, digits=4), :normal, " [ns/b] = [s/GB]\n\t",
            :normal, "clientbandwidth = ", :yellow, round(clientbandwidth, digits=4), :normal, " [ns/b] = [s/GB]")
    else
        success = false
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
    t1 = Vector{Int}()
    t2 = Vector{Int}()
    t3 = Vector{Int}()
    t4 = Vector{Int}()
    browser = ""
    success = true
    while success
        # Measured time interval vectors [ns] for the next browser in line
        # Time measurements are taken only at server; a message pattern
        # is used to distinguish server and client performance
        (browser, t1, t2, t3, t4) = HTS_BCE(SAMPLES, msgsiz)
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
            success = false
        end
    end
end



#
#   Measurements are done. Close server and log file, open results log file.
#
ws_hts.close_hts()
clog(ID, "Closing HTS server")
const RESULTFILE = "benchmark_results.log"
clog(ID, "Results are summarized in ", joinpath(SRCPATH, "logs", RESULTFILE))
fbmr = open(joinpath(SRCPATH, "logs", RESULTFILE), "w")
logto(fbmr)
close(fbm)



#
# Find optimum message size and nominal 100% bandwidths
# Make and store plots and tables
#
test_bestserverbandwidths = Dict{String, Float64}()
test_bestclientbandwidths = Dict{String, Float64}()
test_bestserverlatencies = Dict{String, Float64}()
test_bestclientlatencies = Dict{String, Float64}()
test_plots = Dict()
test_tables = Dict()
test_latency_plots = Dict()
test_latency_tables = Dict()
serverbandwidth = Vector{Float64}()
clientbandwidth = Vector{Float64}()
serverlatency = Vector{Float64}()
clientlatency = Vector{Float64}()
bestserverbandwidth = 0.
bestclientbandwidth = 0.
bestserverlatency = 0.
bestclientlatency = 0.

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
    push!(test_tables,  testid => table(eval.(tvars)..., names = tvars));
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
    push!(test_latency_tables,  testid => table(eval.(tvars)..., names = tvars));

    # Brief output to file and console
    clog_notime(testid, :normal, " Varying message size: \n\t",
        "bestserverbandwidth = ", :yellow,  round(bestserverbandwidth, digits=4), :normal, " [ns/b] = [s/GB]",
        " @ size = ", VSIZE[findfirst(serverbandwidth, bestserverbandwidth)], " b\n\t",
        :normal, "bestclientbandwidth = ", :yellow, round(bestclientbandwidth, digits=4), :normal, " [ns/b] = [s/GB]",
        " @ size = ", VSIZE[findfirst(clientbandwidth, bestclientbandwidth)], " b\n\t",
        "bestserverlatency = ", :yellow,  Int(round(bestserverlatency)), :normal, " [ns] ",
        " @ size = ", VSIZE[findfirst(serverlatency, bestserverlatency)], " b\n\t",
        :normal, "bestclientlatency = ", :yellow, Int(round(bestclientlatency)), :normal, " [ns]",
        " @ size = ", VSIZE[findfirst(clientlatency, bestclientlatency)], " b\n\t"
        )
end


#
#   Full text output
#   The plots are not currently readably encoded in the text file
#

clog_notime(ID, :bold, :yellow, " Plots of all samples :init_plots [ns/b], message size ", INITSIZE, " b ", SAMPLES, " samples" )
foreach(values(init_plots)) do pls
    foreach(values(pls)) do pl
        clog_notime(pl)
    end
end
clog_notime(ID, :bold, :yellow, " Tables of all samples, :init_tables, message size ", INITSIZE, " b ", SAMPLES, " samples" )
for (ke, ta) in  init_tables
    clog_notime(ke, "\n=> ", ta, "\n")
end


clog_notime(ID, :bold, :yellow, " Plots of varying size messages :test_plots [ns/b],\n\t VSIZE = ", VSIZE)
foreach(values(test_plots)) do pls
    foreach(values(pls)) do pl
        clog_notime(pl)
    end
end

clog_notime(ID, :bold, :yellow, " Tables of varying size messages :test_tables [ns/b]")
for (ke, ta) in  test_tables
    clog_notime(ke, "\n=> ", ta, "\n")
end

clog_notime(ID, :bold, :yellow, " Plots of varying size messages :test_latency_plots [ns],\n\t VSIZE = ", VSIZE)
foreach(values(test_latency_plots)) do pls
    foreach(values(pls)) do pl
        clog_notime(pl)
    end
end

clog_notime(ID, :bold, :yellow, " Tables of varying size messages :test_latency_tables [ns]")
for (ke, ta) in  test_latency_tables
    clog_notime(ke, "\n=> ", ta, "\n")
end

clog_notime(ID, :bold, :yellow, " Dictionary  :test_bestserverlatencies [ns]")
for (ke, va) in  test_bestserverlatencies
    clog_notime(ke, " => \t", Int(round(va)))
end

clog_notime(ID, :bold, :yellow, " Dictionary  :test_bestclientlatencies [ns]")
for (ke, va) in  test_bestclientlatencies
    clog_notime(ke, " => \t", Int(round(va)))
end

clog_notime(ID, :bold, :yellow, " Dictionary  :test_bestserverbandwidths [ns/b]")
for (ke, va) in  test_bestserverbandwidths
    clog_notime(ke, " => \t", round(va, digits=4))
end

clog_notime(ID, :bold, :yellow, " Dictionary  :test_bestclientbandwidths [ns/b]")
for (ke, va) in  test_bestclientbandwidths
    clog_notime(ke, " => \t", round(va, digits=4))
end

zflush()
