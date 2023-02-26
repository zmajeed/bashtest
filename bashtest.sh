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

function bashtest_usage {
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

##################################################################

# these functions run in separate processes per testfile
# their output is sent to a separate message reader pid via msgChannel file descriptor

# run all matching tests in one file
# runs in separate process because it sources testfile
# outputs results as bash associative array keyvalue pairs
function bashtest_runOneTestfile {
  local testfile=$1
  local -n testFilters_rotrfef=$2

  local -a allTests
  local -a includedTests
  local -a excludedTests

  bashtest_loadTests $testfile allTests

  local numtests=${#allTests[*]}
  local -A allFuncsResults=(
    [total]=0
    [pass]=0
    [fail]=0
    [skip]=0
  )

  local -A testfuncResults
  local key
  local testfunc
  local result

# dup stdout to variable fd and redirect stdout to messages channel
  exec {stdoutDup}>&1 >&$msgChannel

# apply inclusion filters to run matching tests
  for testfunc in ${allTests[*]}; do
    if bashtest_checkFilters $testfunc testFilters_rotrfef; then
      includedTests+=($testfunc)
      continue
    fi
    testfuncResults[$testfunc]=skip
    excludedTests+=($testfunc)
  done

  echo
  echo "Matched ${#includedTests[*]} out of $numtests tests to run from testfile $testfile"

  bashtest_runAllTests $testfile includedTests testfuncResults

  for result in ${testfuncResults[*]}; do
    let '++allFuncsResults[$result]'
    let '++allFuncsResults[total]'
  done

# close messages channel, restore stdout from dup of stdout
  exec {msgChannel}>&- >&$stdoutDup

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

function bashtest_loadTests {
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
  bashtest_getTestFuncsInfo funcsInfo $testfuncs

# get ordered list of test functions for the testfile
  bashtest_getTestFuncsList $testfile funcsInfo testsList_ltref
}

# run all test functions from a testfile
function bashtest_runAllTests {
  local testfile=$1
  local -n allTests_ratref=$2
  local -n funcResults_ratref=$3

  local testfunc

  for testfunc in ${allTests_ratref[*]}; do
    local result
    bashtest_runOneTest $testfile $testfunc result
    funcResults_ratref[$testfunc]=$result
  done
}

# run one test function
function bashtest_runOneTest {

  local testfile=$1
  local testfunc=$2
  local -n result_rotref=$3

  local es

  echo "testStart: file:$testfile function:$testfunc start_time:$(date -u +%FT%T.%NZ) sender:bashtest_runOneTest:$BASHPID"
  es=$?
  if ((es != 0)); then
    echo >&2 "bashtest_runOneTest.$BASHPID: echo testStart message error $es"
  fi

  $testfunc
  es=$?

  echo "testEnd: file:$testfile function:$testfunc end_time:$(date -u +%FT%T.%NZ) exit_status:$es sender:bashtest_runOneTest:$BASHPID"
  es=$?
  if ((es != 0)); then
    echo >&2 "bashtest_runOneTest.$BASHPID: echo testEnd message error $es"
  fi


  if((es)); then
    result_rotref=fail
  else
    result_rotref=pass
  fi

}

function bashtest_getTestFuncsList {
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
function bashtest_getTestFuncsInfo {
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
function bashtest_checkFilters {
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

# this function runs in separate pid it receives status messages from other children of the main program

function bashtest_statusTracker {
  local msg
  local -A startTimes

  while IFS= read -r msg; do
    local testfile testfunc startTime endTime exitStatus key duration

    case $msg in

# testStart: file:$testfile function:$testfunc start_time:$startTime sender:name,pid,time
      testStart:*)
        if [[ $msg =~ file:([^ ]+) ]]; then
          testfile=${BASH_REMATCH[1]}
        fi
        if [[ $msg =~ function:([^ ]+) ]]; then
          testfunc=${BASH_REMATCH[1]}
        fi
        if [[ $msg =~ start_time:([^ ]+) ]]; then
          startTime=${BASH_REMATCH[1]}
        fi

        key=$testfile:$testfunc
        startTimes[$key]=$startTime
        echo "Run $testfunc from file $testfile.."
      ;;

# testEnd: file:$testfile function:$testfunc end_time:$endTime exit_status:$exitStatus sender:name,pid,time
      testEnd:*)
        if [[ $msg =~ file:([^ ]+) ]]; then
          testfile=${BASH_REMATCH[1]}
        fi
        if [[ $msg =~ function:([^ ]+) ]]; then
          testfunc=${BASH_REMATCH[1]}
        fi
        if [[ $msg =~ end_time:([^ ]+) ]]; then
          endTime=${BASH_REMATCH[1]}
        fi
        if [[ $msg =~ exit_status:([^ ]+) ]]; then
          exitStatus=${BASH_REMATCH[1]}
        fi

        key=$testfile:$testfunc
# printf insures leading zero for fractional seconds that dc omits
        printf -v duration "%.6f" $(echo "9 k $(date +%s.%N -d $endTime) $(date +%s.%N -d ${startTimes[$key]}) - p" | dc)

        if((exitStatus != 0)); then
          echo "Fail $testfunc from $testfile exit status $exitStatus, $duration seconds"
        else
          echo "Pass $testfunc from $testfile, $duration seconds"
        fi
      ;;

    esac
  done

}

#################################################################

# these functions run in main process

# start messages processor that listens to msgChannel
function bashtest_initMessages {
  exec {msgChannel}> >(bashtest_statusTracker)
}

function bashtest_runAllTestfiles {
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

  bashtest_printStartMsg testFilters_ratfref $testfiles

  for testfile in $testfiles; do
# run each testfile in new process to prevent symbol conflicts
# allows concurrent test runs in the future
# capture results for tests in testfile printed to stdout
    local output="$(bashtest_runOneTestfile $testfile testFilters_ratfref)"
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

    bashtest_printTestfileResults $testfile testfileResults
  done

  bashtest_printSummary testfileStatus
  return $netStatus
}

function bashtest_printTestfileResults {
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

function bashtest_printSummary {
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

function bashtest_printStartMsg {
  local -n testfilters_psmref=$1
  local testfiles=${*:2}
  local numtestfiles=$(($# - 1))

  echo "Run tests from $numtestfiles testfiles: $testfiles"
  if ((${#testfilters_psmref[*]} > 0)); then
    echo "Skip tests that do not match regex patterns: ${testfilters_psmref[*]}"
  fi
}

function bashtest_main {
  local -a testFilterPatterns
  local testfiles

  local opt OPTIND=1
  while getopts "hj:t:" opt; do
    case $opt in
      h) bashtest_usage; exit 0
        ;;

      j) maxjobs=$OPTARG
        ;;

      t) testFilterPatterns=(${OPTARG//,/ })
        ;;

      *) bashtest_usage; exit 1
    esac
  done
  shift $((OPTIND - 1))
  : ${maxjobs:=1}

# to clear glob pattern when there's no match
  shopt -s nullglob

  (($# > 0)) && testfiles=$* || testfiles=(*.test.sh)

# file descriptor of channel for messages from child pids
  local msgChannel

  bashtest_initMessages
  bashtest_runAllTestfiles testFilterPatterns ${testfiles[*]}

}

##################################################################

bashtest_main $*


