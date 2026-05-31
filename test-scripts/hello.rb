#!/usr/bin/env ruby
#
# Test Ruby — vérifie que QuickScript exécute correctement les scripts
# .rb, transmet les @param en argv, et expose les variables QS_CONTEXT_*.
#
# @param name=world  Prénom à saluer
#
name = ARGV[0] || "world"

puts "Hello, #{name}!  (ruby #{RUBY_VERSION})"
puts "argv         : #{ARGV.inspect}"
puts "QS_FILE_PATH : #{ENV['QS_CONTEXT_FILE_PATH'] || '(unset)'}"
puts "QS_TARGET    : #{ENV['QS_CONTEXT_TARGET_PATH'] || '(unset)'}"
