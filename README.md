# simulsim
Another attempt at a multiplayer framework.

## Tests
simulsim uses [busted](https://olivinelabs.com/busted/) for running tests, [LuaCov](https://keplerproject.github.io/luacov/) for code coverage, and [Luacov-console](https://github.com/spacewander/luacov-console) for visualizing code coverage.

To get started, install all of these dependencies using [LuaRocks](https://luarocks.org/):

    luarocks install busted
    luarocks install luacov
    luarocks install luacov-console

To run the tests:

    busted tests

To get a code coverage report (after running the tests):

    luacov && luacov-console && luacov-console -s

