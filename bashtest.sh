#!/bin/bash

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
  echo "Run unit tests for bash shell scripts"
  echo "-h: help"
  echo "-t: only run tests that match regex pattern"
  echo "file: test files containing unit test functions, default is all *.test.sh files"
}

# to clear glob pattern when there's no match
shopt -s nullglob

function bashtest_RunAllTestfiles {
  local -n testFilters_ratfref=$1

  local testfiles=${*:2}

  local es testfile
# net success or failure status
  local netStatus=0
  local -A testfileExitStatus

  bashtest_PrintStartMsg testFilters_ratfref $testfiles

  for testfile in $testfiles; do
# run each testfile in new process to prevent symbol conflicts
# allows concurrent test runs in the future
    (bashtest_RunOneTestfile $testfile testFilters_ratfref)
    es=$?
    ((es != 0 && netStatus == 0)) && netStatus=1
    testfileExitStatus[$testfile]=$es
  done

  bashtest_PrintSummary testfileExitStatus
  return $netStatus
}

# run all matching tests in one file
function bashtest_RunOneTestfile {
  local testfile=$1
  local -n testFilters_rotrfef=$2

  local -a allTests

  bashtest_LoadTests $testfile allTests

  local numtests=${#allTests[*]}
  local -A results=(
    [total]=0
    [pass]=0
    [fail]=0
    [skip]=0
  )

  echo
  echo -e "Run $numtests tests from testfile $testfile:"
  bashtest_RunAllTests allTests testFilters_rotrfef results

  bashtest_PrintTestfileResults $testfile results

# succeed if all tests skipped
  (( ${results[skip]} == numtests )) && return 0

# fail if any test faile or no test passes or no tests ran
  return $((${results[fail]} > 0 || ${results[pass]} == 0 || ${results[total]} == 0))
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

# run multiple test functions
function bashtest_RunAllTests {
  local -n allTests_ratref=$1
  local -n testFilters_ratref=$2
  local -n results_ratref=$3

  local testFunc

  for testFunc in ${allTests_ratref[*]}; do
    local result
    bashtest_RunOneTest $testFunc testFilters_ratref result
		let '++results_ratref[$result]'
    let '++results_ratref[total]'
  done
}

# run one test function
function bashtest_RunOneTest {

  local testFunc=$1
  local -n filters_rotref=$2
  local -n result_rotref=$3

  local es

  if ! bashtest_CheckFilters $testFunc filters_rotref; then
    echo
    echo "Skip test function $testFunc"
    result_rotref=skip
    return
  fi

  echo
  echo "Run $testFunc"
  
  $testFunc
  es=$?

	if((es)); then
    echo "Fail test function $testFunc exit status $es"
    result_rotref=fail
  else
    echo "Pass test function $testFunc"
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
    echo "Failed $numfail tests out of $numtests tests from file $testfile"
    echo "Passed $numpass tests out of $numtests tests from file $testfile"
  fi
  echo "Skipped $numskip tests out of $numtests tests from file $testfile"
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

  bashtest_RunAllTestfiles testFilterPatterns ${testfiles[*]}

}

bashtest_Main $*


