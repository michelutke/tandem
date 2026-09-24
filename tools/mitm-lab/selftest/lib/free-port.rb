#!/usr/bin/env ruby
# frozen_string_literal: true

# tools/mitm-lab/selftest/lib/free-port.rb
#
# Prints a TCP port that is free at the moment of the call, for handing to `openssl s_server`
# (which cannot bind to port 0 itself). Small bind/release race is accepted for this local
# self-test only.
require 'socket'

server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
server.close
puts port
