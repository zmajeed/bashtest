#!/bin/bash +x

# bashtest.sh

################################################################################
# MIT License
#
# Copyright (c) 2023 Zartaj Majeed
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
################################################################################

function bashtest_Usage {
  echo "Usage: bashtest.sh [-t pattern] [file ...]"
  echo "Run unit tests for bash shell scripts, unit tests are functions with TEST_ prefix"
  echo "-h: help"
  echo "-t: only run tests that match regex pattern"
  echo "file: test files containing unit test functions, default is all *.test.sh files"
  echo
  echo "Examples:"
  echo "bashtest.sh"
  echo "bashtest.sh date*.test.sh"
}

# to clear glob pattern when there's no match
shopt -s nullglob

##################################################################

# these functions run in separate processes per testfile
# their output is sent to a separate message reader pid via msgChannel file descriptor

# run all matching tests in one file
# runs in separate process because it sources testfile
# outputs results as bash associative array keyvalue pairs
function bashtest_RunOneTestfile {
  local testfile=$1
  local -n testFilters_rotrfef=$2

  local -a allTests
  local -a includedTests
  local -a excludedTests

  bashtest_LoadTests $testfile allTests

  local numtests=${#allTests[*]}
  local -A allFuncsResults=(
    [total]=0
    [pass]=0
    [fail]=0
    [skip]=0
  )

  local -A testFuncResults
  local key
  local testFunc
  local result

# dup stdout to fd 3 and redirect stdout to messages channel
  exec 3>&1 >&$msgChannel

# apply inclusion filters to run matching tests
  for testFunc in ${allTests[*]}; do
    if bashtest_CheckFilters $testFunc testFilters_rotrfef; then
      includedTests+=($testFunc)
      continue
    fi
    testFuncResults[$testFunc]=skip
    excludedTests+=($testFunc)
  done

  echo
  echo "Matched ${#includedTests[*]} out of $numtests tests to run from testfile $testfile"
  bashtest_RunAllTests includedTests testFuncResults

  for result in ${testFuncResults[*]}; do
    let '++allFuncsResults[$result]'
    let '++allFuncsResults[total]'
  done

# close messages channel, restore stdout from fd 3
  exec {msgChannel}>&- >&3

# @A operator prints complete definition of associative array "declare -A results=(... )"
  local output=${allFuncsResults[*]@A}
# strip everything from start to opening parenthesis
  output=${output#*(}
# strip trailing space and closing parenthesis
  output=${output:0:-2}
# return results for caller to capture
  echo "$output"

# succeed if all tests skipped
  (( ${allFuncsResults[skip]} == numtests )) && return 0

# fail if any test faile or no test passes or no tests ran
  return $((${allFuncsResults[fail]} > 0 || ${allFuncsResults[pass]} == 0 || ${allFuncsResults[total]} == 0))
}

function bashtest_LoadTests {
  local testfile=$1
  local -n testsList_ltref=$2

  local testfuncs

# source testfile to pull in test functions
  shopt -u sourcepath
  . $testfile

# get all test function names
  testfuncs=$(declare -F | cut -d' ' -f3 | grep '^TEST_')

# then get source file and line info for each test function
  local -a funcsInfo
  bashtest_GetTestFuncsInfo funcsInfo $testfuncs

# get ordered list of test functions for the testfile
  bashtest_GetTestFuncsList $testfile funcsInfo testsList_ltref
}

function bashtest_PrintStartMsg {
  local -n testfilters_psmref=$1
  local testfiles=${*:2}
  local numtestfiles=$(($# - 1))

  echo "Run tests from $numtestfiles testfiles: $testfiles"
  if ((${#testfilters_psmref[*]} > 0)); then
    echo "Skip tests that do not match regex patterns: ${testfilters_psmref[*]}"
  fi
}

# run multiple test functions
function bashtest_RunAllTests {
  local -n allTests_ratref=$1
  local -n funcResults_ratref=$2

  local testFunc

  for testFunc in ${allTests_ratref[*]}; do
    local result
    bashtest_RunOneTest $testFunc result
    funcResults_ratref[$testFunc]=$result
  done
}

# run one test function
function bashtest_RunOneTest {

  local testFunc=$1
  local -n result_rotref=$2

  local es

  echo
  echo "Run $testFunc"
  
  $testFunc
  es=$?

  if((es)); then
    echo "Fail $testFunc exit status $es"
    result_rotref=fail
  else
    echo "Pass $testFunc"
    result_rotref=pass
  fi

}

function bashtest_GetTestFuncsList {
  local testfile=$1
  local -n funcsInfo_gtflref=$2
  local -n testsList_gtflref=$3

  local i

  for((i = 0; i < ${#funcsInfo_gtflref[*]}; ++i)); do
    local -a info=(${funcsInfo_gtflref[i]})
    local funcname=${info[0]}
    local filename=${info[2]}

# skip function from all files except testfile

    [[ $filename == $testfile ]] || continue
    testsList_gtflref+=($funcname)
  done

}

# fill array with functions info
# info format: funcname line filename
function bashtest_GetTestFuncsInfo {
  local -n info_gfiref=$1
  local funcs=${*:2}

  local cmdout

# function info sorted by filename and line number
  cmdout=$(
    declare func
    shopt -s extdebug
    for func in $funcs; do
      declare -F $func
    done |
    sort -k3,3 -k2,2n
  )

# split on newline
# each line looks like:
# function line file
# TEST_a_unit_test 107 protojson.test.sh

  IFS=$'\n'
  info_gfiref=($cmdout)
  unset IFS
}

# filters match for inclusion
# returns 0 for successful match if there are no filters or str matches one of the filters
function bashtest_CheckFilters {
  local str=$1
  local -n filters_cfref=$2
  local n=${#filters_cfref[*]}

# return if no filter to match against
  ((n == 0)) && return 0

  local i

  for((i = 0; i < n; ++i)); do
    if [[ $str =~ ${filters_cfref[i]} ]]; then
      return 0
    fi
  done

# no filter for inclusion was matched
  return 1
}

#################################################################

# this function runs in separate pid to receive messages from other children of the main program

function bashtest_ReadMessages {
  local msg
  while IFS= read -r msg; do
    #echo -n "ReadMessages: "
    echo "$msg"
  done

}

#################################################################

# these functions run in main process

# start messages processor that listens to msgChannel
function bashtest_InitMessages {
  exec {msgChannel}> >(bashtest_ReadMessages)
}

function bashtest_RunAllTestfiles {
  local -n testFilters_ratfref=$1

  local testfiles=${*:2}

  local es testfile
# net success or failure status
  local netStatus=0
# status per testfile
  local -A testfileStatus
# cumulative results
  local -A allFilesResults=(
    [total]=0
    [pass]=0
    [fail]=0
    [skip]=0
  )

  local key

  bashtest_PrintStartMsg testFilters_ratfref $testfiles

  for testfile in $testfiles; do
# run each testfile in new process to prevent symbol conflicts
# allows concurrent test runs in the future
# capture results for tests in testfile printed to stdout
    local output="$(bashtest_RunOneTestfile $testfile testFilters_ratfref)"
    es=$?
    ((es != 0 && netStatus == 0)) && netStatus=1
    testfileStatus[$testfile]=$es

# create dynamic associative array from testfile results
# note quotes are required around parentheses
    local -A testfileResults="($output)"

# update cumulative results
    for key in ${!allFilesResults[*]}; do
      let 'allFilesResults[$key] += testfileResults[$key]'
    done

    bashtest_PrintTestfileResults $testfile testfileResults
  done

  bashtest_PrintSummary testfileStatus
  return $netStatus
}

function bashtest_PrintTestfileResults {
  local file=$1
  local -n testfileResults_ptref=$2
  local numtests=${testfileResults_ptref[total]}
  local numpass=${testfileResults_ptref[pass]}
  local numfail=${testfileResults_ptref[fail]}
  local numskip=${testfileResults_ptref[skip]}

  echo

  if ((numfail == 0 && numskip == 0)); then
    echo "Passed $numtests tests from file $testfile"
  elif ((numpass == 0 && numskip == 0)); then
    echo "Failed all $numtests tests from file $testfile"
  else
    echo "Failed $numfail out of $numtests tests from file $testfile"
    echo "Passed $numpass out of $numtests tests from file $testfile"
  fi
  echo "Skipped $numskip out of $numtests tests from file $testfile"
}

function bashtest_PrintSummary {
  local -n results_psref=$1
  local file es

  echo
  echo "Results summary for all tests:"

  for file in ${!results_psref[*]}; do
    es=${results_psref[$file]}
    ((es == 0)) && status="Passed all" || status="Failed some"
    echo "$status tests from file $file"
  done
}

function bashtest_Main {
  local -a testFilterPatterns
  local testfiles

  local opt OPTIND=1
  while getopts "ht:" opt; do
    case $opt in
      h) bashtest_Usage; exit 0
        ;;

      t) testFilterPatterns=(${OPTARG//,/ })
        ;;

      *) bashtest_Usage; exit 1
    esac
  done
  shift $((OPTIND - 1))

  (($# > 0)) && testfiles=$* || testfiles=(*.test.sh)

# file descriptor of channel for messages from child pids
  local msgChannel

  bashtest_InitMessages
  bashtest_RunAllTestfiles testFilterPatterns ${testfiles[*]}

}

##################################################################

bashtest_Main $*


