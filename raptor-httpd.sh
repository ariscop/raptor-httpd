#!/bin/bash

serve-cgi() {
    export \
    SERVER_SOFTWARE="Raptor Httpd" \
    SERVER_NAME="localhost" \
    SERVER_ADDR="127.0.0.1" \
    SERVER_PORT="8080" \
    GATEWAY_INTERFACE="CGI/1.1" \
    SERVER_PROTOCOL="HTTP/1.0" \
    REQUEST_METHOD="$1" \
    SCRIPT_NAME="$2" \
    QUERY_STRING="$3" \
    SCRIPT_FILENAME="$4"

    # — the part of URL after ? character. May be composed of *name=value pairs separated with ampersands (such as var1=val1&var2=val2…) when used to submit form data transferred via GET method as defined by HTML application/x-www-form-urlencoded.
    #REMOTE_HOST — host name of the client, unset if server did not perform such lookup.
    #REMOTE_ADDR — IP address of the client (dot-decimal).
    #AUTH_TYPE — identification type, if applicable.
    #REMOTE_USER used for certain AUTH_TYPEs.
    #REMOTE_IDENT — see ident, only if server performed such lookup.
    #CONTENT_TYPE — MIME type of input data if PUT or POST method are used, as provided via HTTP header.
    #CONTENT_LENGTH — similarly, size of input data (decimal, in octets) if provided via HTTP header.
    #Variables passed by user agent (HTTP_ACCEPT, HTTP_ACCEPT_LANGUAGE, HTTP_USER_AGENT, HTTP_COOKIE and possibly others) contain values of corresponding HTTP headers and therefore have the same sense.
	
	echo running php
	echo "HTTP/1.0 200 OK" >&3
	php-cgi 0<&3 1>&3
    
    #PATH_INFO="$2" — path suffix, if appended to URL after program name and a slash.
    #PATH_TRANSLATED="$3" — corresponding full path as supposed by server, if PATH_INFO is present.
}


serve-file() {
	MIMETYPE="`file --mime-type -b "$1"`"
	echo "HTTP/1.0 200 OK" >&3
	echo "Content-Type: $MIMETYPE" >&3
	echo >&3
	echo "$1" 200 "$MIMETYPE"
	cat "$FILENAME" >&3
}

serve-dir() {
	echo "HTTP/1.0 200 OK" >&3
	echo "Content-Type: text/plain" >&3
	echo >&3
	echo "$1" 200 text/plain directory listing
	echo "Directory listing of " "$1" >&3
	ls -l "$1" 1>&3 2>&3
}

do-403() {
	echo "HTTP/1.0 403 Forbidden\n" >&3
	echo >&3
}

do-404() {
	echo "HTTP/1.0 404 File Not Found\n" >&3
	echo >&3
	echo "$FILENAME" not found
}



http-accept() {
	read -r REQ <&3
		
	echo "$REQ"
	
	################
	parse-line() {
		echo "$1" | cut -d: -f1 |
			sed -E 's:[^a-zA-Z0-9]:_:g;s/.$//g' |
			tr '[:lower:]' '[:upper:]'
	}
	
	read -r LINE <&3
	
	HEAD=`parse-line "$LINE"`
	while [ "$HEAD" ]; do
		export HTTP_$HEAD="`echo "$LINE" | cut -d" " -f2-`"
		read -r LINE <&3
		HEAD=`parse-line "$LINE"`
	done
	################
	# ^^ its best this is left alone
	
	METHOD="`echo "$REQ" | cut -d' ' -f1`"
	REQ="`echo "$REQ" | cut -d' ' -f2`"
	REQPATH="`echo $REQ | cut -d? -f1`"
	QUERY="`echo $REQ | cut -d? -f2`"
	FILENAME="$DOCUMENT_ROOT$REQPATH"
	
	export FILENAME
	
	#block ..
	if [ `echo $FILENAME | grep -F ".."` ]; then
		do-403
		return
	fi
	
	case "$METHOD" in
		"GET")
			if [ -r "$FILENAME" ] ; then
				if [ -f "$FILENAME" ]; then
					if [[ "$REQPATH" == "${REQPATH%.php}.php" ]] ; then
						echo running serve-cgi
						serve-cgi "$METHOD" "$REQPATH" "$QUERY" "$FILENAME"
					else
						serve-file "$FILENAME"
					fi
				elif [ -d "$FILENAME" ]; then
					serve-dir "$FILENAME"
				else
					do-404
				fi
			else
				do-404
			fi
			;;
		*)
			do-403
			;;
	esac
}

if [[ $MODE == "child" ]] ; then
	http-accept
	exit
fi


if [ "$1" ]; then
	if [ ! -d "$1" ] || [ ! -r "$1" ]; then
		echo invalid directory
		exit
	else
		export DOCUMENT_ROOT=`echo $1 | sed -E s:/?$:/:`
	fi
else
	export DOCUMENT_ROOT="`pwd`/"
fi

echo Starting Raptor-httpd. prepare to be eaten

MODE=child socat TCP-LISTEN:8080,reuseaddr,fork EXEC:$0,fdin=3,fdout=3


