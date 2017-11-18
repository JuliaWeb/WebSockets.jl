# Included in runtests at the end.
"Get application path for developer applications"
function fwhich(s)
    fi = ""
    if Sys.is_windows()
        try
            fi = split(readstring(`where.exe $s`), "\r\n")[1]
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
    # windows accepts english paths anywhere.
    # Forward slash acceptable too.
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
function launch_command(shortbrowsername)
    url = "http://127.0.0.1:8080/browsertest.html"
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
        return Cmd(`$pt phantom.js $url`)
    else
        if Sys.is_windows()
            Cmd( [ pt, url , prsw])
        else
            if Sys.is_apple()
                return Cmd(`open --fresh -n $url -a $pt --args $prsw`)
            elseif Sys.is_linux() || Sys.is_bsd()
                return Cmd(`xdg-open $(url) $pt`)
            end
        end
    end
end


function open_testpage(shortbrowsername)
    dmc = launch_command(shortbrowsername)
    if dmc == ``
        info("\tCould not find " * shortbrowsername)
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
            info("\tFailed to spawn " * shortbrowsername)
            return false
        end
    end
    return true
end
function open_all_browsers()
    info("Try to open browsers")
    brs = ["chrome", "firefox", "iexplore", "safari", "phantomjs"]
    openbrowsers = 0
    for b in brs
        openbrowsers += open_testpage(b)
        sleep(8) # Reduce simultaneous connections to server. This is not a httpserver stress test. width:  
    end
    info("Out of google chrome, firefox, iexplore, safari and phantomjs, tried to spawn ", openbrowsers)
    openbrowsers
end
