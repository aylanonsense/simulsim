# simulsim
Another attempt at a multiplayer framework.

## Tests
simulsim uses [busted](https://olivinelabs.com/busted/) for running tests, [LuaCOv](https://keplerproject.github.io/luacov/) for code coverage, and [Luacov-console](https://github.com/spacewander/luacov-console) for code coverage visualization.

To get started, install all of the dependencies above using [LuaRocks](https://luarocks.org/):
    luarocks install busted
    luarocks install luacov
    luarocks install luacov-console

To run the unit tests:
    busted ./tests

To get a code coverage report:
    luacov && luacov-console && luacov-console -s

