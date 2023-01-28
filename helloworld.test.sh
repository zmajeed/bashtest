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

