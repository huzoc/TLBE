#!/usr/bin/env lua

local lu = require("luaunit")

require("follow-player")
require("follow-base")
require("follow-rocket")

os.exit(lu.LuaUnit:run())
