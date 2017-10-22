# Included in runtests at the end. For windows systems so far.

function browser_path(shortname)
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
	return ""
end 
"""backticks black magic workaround...
Know no fix for programs in registry, e.g. for cmd > `start chrome`"""
function launch_command(shortbrowsername)
	url = "http://localhost:8080/browsertest.html"
	pt = browser_path(shortbrowsername)
	pt == "" && return ``
	if shortbrowsername == "iexplore"
		prsw = "-private"
	else
		prsw = "--incognito"
	end
	Cmd( [ pt, url , prsw])
end 

function open_testpage(shortbrowsername) 
	dmc = launch_command(shortbrowsername)
	if dmc == ``
		info("\tCould not find " * shortbrowsername)
		return false
	else
		try
			spawn(dmc)
		catch
			info("\tFailed to open " * shortbrowsername)
			return false
		end
	end 
	return true
end 
function open_all_browsers()
	info("Try to open browsers")
	openbrowsers = 0
	openbrowsers += open_testpage("chrome") 
	openbrowsers += open_testpage("firefox")
	openbrowsers += open_testpage("iexplore") 
	openbrowsers += open_testpage("safari") 
	openbrowsers
end

