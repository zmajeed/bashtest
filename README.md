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
bashtest.sh date*.test.sh
```
