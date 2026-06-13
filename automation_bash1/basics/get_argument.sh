#!/bin/bash

# check is user provided an argument
if [ -z "$1" ]
then 
	echo "Usage: $0 <name>"
	exit 1
fi

# the first argument is "$1"
# the second argument is "$2"
NAME="$1"

if [ "$NAME" = "Allan" ]
then
	echo "Welcome Allan"
else
	echo "Unknown user"
fi