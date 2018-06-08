#!/bin/bash

msg "Writing Error files in /var/www/html"

setup_varwwwhtml_error 400 "Bad request"
setup_varwwwhtml_error 403 "Forbidden"
setup_varwwwhtml_error 404 "Not found."

setup_varwwwhtml_error 408 "Request timeout"
setup_varwwwhtml_error 414 "Request URI too long!"
setup_varwwwhtml_error 500 "An internal server error occurred. Please try apgain later."
setup_varwwwhtml_error 501 "This method may not be used."
setup_varwwwhtml_error 502 "Bad Gateway"
setup_varwwwhtml_error 503 "The service is not available. Please try again later."
setup_varwwwhtml_error 504 "Gateway timeout error"

