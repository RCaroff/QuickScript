#!/usr/bin/env perl
#
# Perl test — checks that QuickScript correctly runs
# .pl, passes the @param values in argv, and exposes the QS_CONTEXT_*
# variables.
#
# @param name=world  Name to greet
#
use strict;
use warnings;

my $name = $ARGV[0] // "world";

print "Hello, $name!  (perl $])\n";
print "argv         : @ARGV\n";
print "QS_FILE_PATH : ", ($ENV{QS_CONTEXT_FILE_PATH}   // "(unset)"), "\n";
print "QS_TARGET    : ", ($ENV{QS_CONTEXT_TARGET_PATH} // "(unset)"), "\n";
