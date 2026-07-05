// modules/gui/srvctl-gui/scripts.js - leftover jQuery snippet (DORMANT
// module). FIXME(v4): dead file - referenced by no page (index.html and
// wetty.html do not load it) and jQuery is never served; remove with the
// module retirement.
$(document).ready(function(){$(".alert").addClass("in").fadeOut(4500);

/* swap open/close side menu icons */
$('[data-toggle=collapse]').click(function(){
  	// toggle icon
  	$(this).find("i").toggleClass("glyphicon-chevron-right glyphicon-chevron-down");
});
});