# Included in benchmark_prepare.jl and in browsertests.jl
# Refers logutils
if !@isdefined(SRCPATH)
    const SRCPATH = Base.source_dir() == nothing ? Pkg.dir("WebSockets", "benchmark") : Base.source_dir()
    const LOGGINGPATH = realpath(joinpath(SRCPATH, "../logutils/"))
    SRCPATH ∉ LOAD_PATH && push!(LOAD_PATH, SRCPATH)
    LOGGINGPATH ∉ LOAD_PATH && push!(LOAD_PATH, LOGGINGPATH)
end
using logutils_ws

"A list of potentially available browsers, to be tried in succession if present"
const BROWSERS = ["chrome", "firefox", "iexplore", "safari", "phantomjs"]
"An complicated browser counter."
mutable struct Countbrowser;value::Int;end
(c::Countbrowser)() =COUNTBROWSER.value += 1
"For next value: COUNTBROWSER(). For current value: COUNTBROWSER.value"
const COUNTBROWSER = Countbrowser(0)
const PORT = [8000]
const PAGE = ["bce.html"]
const URL = ["http://127.0.0.1:$(PORT[1])/$(PAGE[1])"]



"Get application path for developer applications"
function fwhich(s)
    fi = ""
    if Sys.is_windows()
        try
            fi = split(read(`where.exe $s`, String), "\r\n")[1]
            if !isfile(fi)
                fi = ""
            end
        catch
            fi =""
        end
    else
        try
            fi = readchomp(`which $s`)
        catch
            fi =""
        end
    end
    fi
end
function browser_path_unix_apple(shortname)
    trypath = ""
    if shortname == "chrome"
        if Base.Sys.is_apple()
            return "Google Chrome"
        else
            return "google-chrome"
        end
    end
    if shortname == "firefox"
        return "firefox"
    end
    if shortname == "safari"
        if Base.Sys.is_apple()
            return "safari"
        else
            return ""
        end
    end
    if shortname == "phantomjs"
        return fwhich(shortname)
    end
    return ""
end
function browser_path_windows(shortname)
    # windows accepts English paths anywhere.
    # Forward slash is acceptable too.
    # Searches C and D drives....
    trypath = ""
    homdr = ENV["HOMEDRIVE"]
    path32 = homdr * "/Program Files (x86)/"
    path64 = homdr * "/Program Files/"
    if shortname == "chrome"
        trypath = path64 * "Chrome/Application/chrome.exe"
        isfile(trypath) && return trypath
        trypath = path32 * "Google/Chrome/Application/chrome.exe"
        isfile(trypath) && return trypath
    end
    if shortname == "firefox"
        trypath = path64 * "Mozilla Firefox/firefox.exe"
        isfile(trypath) && return trypath
        trypath = path32 * "Mozilla Firefox/firefox.exe"
        isfile(trypath) && return trypath
    end
    if shortname == "safari"
        trypath = path64 * "Safari/Safari.exe"
        isfile(trypath) && return trypath
        trypath = path32 * "Safari/Safari.exe"
        isfile(trypath) && return trypath
    end
    if shortname == "iexplore"
        trypath = path64 * "Internet Explorer/iexplore.exe"
        isfile(trypath) && return trypath
        trypath = path32 * "Internet Explorer/iexplore.exe"
        isfile(trypath) && return trypath
    end
    if shortname == "phantomjs"
        return fwhich(shortname)
    end
    return ""
end
"Constructs launch command"
function launch_command(shortbrowsername)
    if Sys.is_windows()
        pt = browser_path_windows(shortbrowsername)
    else
        pt = browser_path_unix_apple(shortbrowsername)
    end
    pt == "" && return ``
    if shortbrowsername == "iexplore"
        prsw = "-private"
    else
        prsw = "--incognito"
    end
    if shortbrowsername == "phantomjs"
        if isdefined(:SRCPATH)
            script = joinpath(SRCPATH, "phantom.js")
        else
            script = "phantom.js"
        end
        return Cmd(`$pt $script $URL`)
    else
        if Sys.is_windows()
            return Cmd( [ pt, URL, prsw])
        else
            if Sys.is_apple()
                return Cmd(`open --fresh -n $URL -a $pt --args $prsw`)
            elseif Sys.is_linux() || Sys.is_bsd()
                return Cmd(`xdg-open $(URL) $pt`)
            end
        end
    end
end


function open_testpage(shortbrowsername)
    id = "open_testpage"
    dmc = launch_command(shortbrowsername)
    if dmc == ``
        clog(id, "Could not find " * shortbrowsername)
        return false
    else
        try
            if shortbrowsername == "phantomjs"
                # Run enables text output of phantom messages in the REPL. In Windows
                # standalone REPL, run will freeze the main thread if not run async.
                @async run(dmc)
            else
                spawn(dmc)
            end
        catch
            clog(id, :red, "Failed to spawn " * shortbrowsername)
            return false
        end
    end
    return true
end

"Try to open one browser from BROWSERS.
In some cases we expect an immediate indication
of failure, for example when the corresponding browser
is not found on the system. In other cases, we will
just wait in vain. In those cases,
call this function again after a reasonable timeout.
The function remembers which browsers were tried before.
"
function open_a_browser()
    id = "open_next_browser"
    if COUNTBROWSER.value > length(BROWSERS)
        return false
    end
    success = false
    b = ""
    while COUNTBROWSER.value < length(BROWSERS) && !success
        b = BROWSERS[COUNTBROWSER()]
        clog(id, "Trying to launch browser no. ", COUNTBROWSER.value, ", ", :yellow, b)
        success = open_testpage(b)
    end
    success && clog(id, "seems to work:", :yellow, b, :normal, " on ", URL)
    success, b
end
