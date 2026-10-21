#!/usr/bin/env ruby
#
# Ruby test — checks that QuickScript correctly runs
# .rb, passes the @param values in argv, and exposes the QS_CONTEXT_*
# variables.
#
# @param name=world  Name to greet
#
name = ARGV[0] || "world"

puts "Hello, #{name}!  (ruby #{RUBY_VERSION})"
puts "argv         : #{ARGV.inspect}"
puts "QS_FILE_PATH : #{ENV['QS_CONTEXT_FILE_PATH'] || '(unset)'}"
puts "QS_TARGET    : #{ENV['QS_CONTEXT_TARGET_PATH'] || '(unset)'}"
