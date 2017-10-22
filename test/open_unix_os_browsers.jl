# Included in runtests at the end. 

# not tested locally, just travis.
function launch_command(shortbrowsername)
	url = "http://localhost:8080/browsertest.html"
	shortbrowsername == "" && return ``
	if Sys.is_apple()
        return Cmd(`open $shortbrowsername $(url)`)
    elseif Sys.is_linux() || Sys.is_bsd()
        return Cmd(`xdg-open $shortbrowsername $(url)`)
	end
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
	openbrowsers += open_testpage("PhantomJS") 
	openbrowsers
end

