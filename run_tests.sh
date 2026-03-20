#!/bin/bash
# ABOUTME: Runs busted tests inside Neovim headless mode
# ABOUTME: Provides vim API access that tests require

eval "$(luarocks --lua-version 5.1 path)"

nvim --headless -u NONE \
  --cmd "set rtp+=." \
  -c "lua package.path = 'lua/?.lua;lua/?/init.lua;' .. package.path .. ';' .. (os.getenv('LUA_PATH') or '')" \
  -c "lua package.cpath = package.cpath .. ';' .. (os.getenv('LUA_CPATH') or '')" \
  -c "lua require('busted.runner')({ standalone = false, output = 'utfTerminal', ROOT = {'tests'}, pattern = '_spec' })" \
  -c "qall!"
