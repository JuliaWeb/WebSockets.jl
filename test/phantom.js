// Note that the console log output does not appear in Julia REPL when
// this is called using spawn. For debugging, use "run". These functions
// are run in a shell outside the web page.
var page = require('webpage').create(),
  system = require('system'),
  t, address;

if (system.args.length === 1) {
  console.log('Phantomjs.js: too few arguments. Need phantom.js <some URL>');
  phantom.exit();
}
console.log('PhantomJS: The default user agent is ' + page.settings.userAgent);
page.settings.userAgent = 'PhantomJS';
console.log('PhantomJS: User agent set to ' + page.settings.userAgent);


t = Date.now();
address = system.args[1];
page.open(address, function(status) {
    if (status !== 'success') {
      console.log('FAIL to load the address');
    } else {
      t = Date.now() - t;
      console.log('PhantomJS loading ' + system.args[1]);
      console.log('PhantomJS loading time ' + t + ' msec');
      window.setTimeout( (function() {
                                    page.render("phantomjs.png");
                                    console.log("PhantomJS saved render, exits after 30s")
                                    phantom.exit()
                                  }),
                       30000)
    }
  }
);
