# bashtest
Run unit tests for bash shell scripts


## Usage

```
Usage: bashtest.sh [-t pattern] [file ...]
Run unit tests for bash shell scripts, unit tests are functions with TEST_ prefix
-h: help
-t: only run tests that match regex pattern
file: test files containing unit test functions, default is all *.test.sh files

Examples:
bashtest.sh
bashtest.sh helloworld.test.sh
```

**`bashtest`** is a simple test runner for unit testing bash scripts. Unit tests are bash functions that start with `TEST_`, e.g. `TEST_hello_world`.

**`bashtest`** loads these functions from files ending in `.test.sh` in the current directory by default. It runs all the `TEST_*` functions and reports their results.

It prints whether each test passed or failed or was skipped. A test passes if its exit status is 0, it fails otherwise.

A test is skipped if it does not match the test inclusion pattern provided with the `-t` option

A sample script `helloworld.sh` is provided along with a test file `helloworld.test.sh`


## Writing unit tests for `bash` scripts

This is how I write unit tests for `bash` scripts

In the main script

1. Set a variable, say `testing`, to check if the script should run normally, e.g. `testing=false` or is being tested, i.e. `testing=true`
2. Set the default value of `testing` to `false`
3. Check the variable before the main part of the script runs. If `testing` is `true`, return from the script. This way when the script is sourced by the testing script, all necessary functions and variables will be defined but the main part of the script will not execute.

In the testfile, at the very top

1. Set `testing` to `true`
2. Source the main script

## An example

The main script `helloworld.sh`

```bash

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
```

The testfile `helloworld.test.sh`

```bash
# helloworld.test.sh

# source script containing functions to test
# set testing=true to prevent main script in helloworld.sh from running

testing=true . helloworld.sh

function TEST_hello_world {
  local name=World
  [[ $(hello $name) == "Hello $name!" ]]
}

function TEST_hello_le_monde {
  local name="Le Monde"
  [[ $(hello "$name") == "Hello $name!" ]]
}
```

Running `helloworld.sh` directly produces normal output

```
$ ./helloworld.sh World

Hello World!
```

Running **`bashtest`** runs the unit tests from `helloworld.test.sh` and does not run the main part of `helloworld.sh`

```
$ bashtest.sh

Run tests from 1 testfiles: helloworld.test.sh

Matched 3 out of 3 tests to run from testfile helloworld.test.sh:

Run TEST_hello_one_word
Pass TEST_hello_one_word

Run TEST_hello_two_words
Pass TEST_hello_two_words

Run TEST_hello_no_words
Pass TEST_hello_no_words

Passed 3 tests from file helloworld.test.sh
Skipped 0 out of 3 tests from file helloworld.test.sh

Results summary for all tests:
Passed all tests from file helloworld.test.sh
```

## Filtering tests

A regular expression may be given with the `-t` option to only run tests that match


```
$ bashtest.sh -t "one|two"

Run tests from 1 testfiles: helloworld.test.sh
Skip tests that do not match regex patterns: one|two

Matched 2 out of 3 tests to run from testfile helloworld.test.sh

Run TEST_hello_one_word
Pass TEST_hello_one_word

Run TEST_hello_two_words
Pass TEST_hello_two_words

Failed 0 out of 3 tests from file helloworld.test.sh
Passed 2 out of 3 tests from file helloworld.test.sh
Skipped 1 out of 3 tests from file helloworld.test.sh

Results summary for all tests:
Passed all tests from file helloworld.test.sh
```
