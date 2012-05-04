#!/bin/bash

serve_cgi() {
    export \
    SCRIPT_NAME="$DOCUMENT_URI" \
    SCRIPT_FILENAME="$1" \
    REDIRECT_STATUS=200
    	
	echo running php
	echo "HTTP/1.0 200 OK" >&3
	php-cgi 0<&3 1>&3
    
    #PATH_INFO="$2" — path suffix, if appended to URL after program name and a slash.
    #PATH_TRANSLATED="$3" — corresponding full path as supposed by server, if PATH_INFO is present.
}


serve_file() {
	MIMETYPE="`file --mime-type -b \"$1\"`"
	echo \
"HTTP/1.0 200 OK
Content-Type: $MIMETYPE

" >&3
	cat "$FILENAME" >&3
}

serve_dir() {
	echo \
"HTTP/1.0 200 OK
Content-Type: text/plain

$1 200 text/plain directory listing
Directory listing of $1
" >&3
	ls -l "$1" 1>&3 2>&3
}

do_403() {
	echo "HTTP/1.0 403 Forbidden\n" >&3
	echo >&3
}

do_404() {
	echo "HTTP/1.0 404 File Not Found\n" >&3
	echo >&3
	echo "$FILENAME" not found
}

do_rewrite() {
	if [ ! -f "$FILENAME" ]; then
		export FILENAME="$DOCUMENT_ROOT"/index.php
	fi
}

http_accept() {
	read -r REQ <&3
		
	echo "$REQ"
	
	################
	parse_line() {
		echo "$1" | cut -d: -f1 |
			sed -E 's:[^a-zA-Z0-9]:_:g;s/.$//g' |
			tr '[:lower:]' '[:upper:]'
	}
	
	read -r LINE <&3
	
	HEAD=`parse_line "$LINE"`
	while [ "$HEAD" ]; do
		export HTTP_$HEAD="`echo \"$LINE\" | cut -d\  -f2-`"
		read -r LINE <&3
		HEAD=`parse_line "$LINE"`
	done
	################
	# ^^ its best this is left alone
	
	export	REQUEST_URI="`echo \"$REQ\" | cut -d' ' -f2`"
	export  DOCUMENT_URI="`echo \"$REQUEST_URI\" | cut -d? -f1`" \
			QUERY_STRING="`echo \"$REQUEST_URI\" | cut -d? -f2`" \
			SERVER_SOFTWARE="Raptor Httpd" \
			SERVER_NAME="localhost" \
			SERVER_ADDR="127.0.0.1" \
			SERVER_PORT="8080" \
			GATEWAY_INTERFACE="CGI/1.1" \
			SERVER_PROTOCOL="HTTP/1.0" \
			REQUEST_METHOD="`echo \"$REQ\" | cut -d' ' -f1`"
	export	FILENAME="$DOCUMENT_ROOT$DOCUMENT_URI"
	
	#block ..
	if [ `echo $FILENAME | grep -F ".."` ]; then
		do_403
		return
	fi
	
	do_rewrite
	echo serving "$FILENAME"
	
	case "$REQUEST_METHOD" in
		"GET")
			if [ -r "$FILENAME" ] ; then
				if [ -f "$FILENAME" ]; then
					if [[ "$FILENAME" == "${FILENAME%.php}.php" ]] ; then
						echo running serve_cgi
						serve_cgi "$FILENAME"
					else
						serve_file "$FILENAME"
					fi
				elif [ -d "$FILENAME" ]; then
					serve_dir "$FILENAME"
				else
					do_404
				fi
			else
				do_404
			fi
			;;
		*)
			do_403
			;;
	esac
}

if [[ "$MODE" == "child" ]] ; then
	http_accept
	exit
fi


if [ "$1" ]; then
	if [ ! -d "$1" ] || [ ! -r "$1" ]; then
		echo invalid directory
		exit
	else
		export DOCUMENT_ROOT=`echo $1 | sed -r s:/?$:/:`
	fi
else
	export DOCUMENT_ROOT="`pwd`/"
fi

echo Starting Raptor-httpd. prepare to be eaten

MODE=child socat TCP-LISTEN:8080,reuseaddr,fork EXEC:$0,fdin=3,fdout=3


