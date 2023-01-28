#!/bin/bash

# helloworld.sh

function hello {
  echo "Hello $1!"
}


# default value of testing is false so return does not occur and main script runs
# set testing=true before sourcing this script for testing to prevent main script from running
${testing:=false} && return

# main
hello "$1"
