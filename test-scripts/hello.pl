#!/usr/bin/env perl
#
# Test Perl — vérifie que QuickScript exécute correctement les scripts
# .pl, transmet les @param en argv, et expose les variables QS_CONTEXT_*.
#
# @param name=world  Prénom à saluer
#
use strict;
use warnings;

my $name = $ARGV[0] // "world";

print "Hello, $name!  (perl $])\n";
print "argv         : @ARGV\n";
print "QS_FILE_PATH : ", ($ENV{QS_CONTEXT_FILE_PATH}   // "(unset)"), "\n";
print "QS_TARGET    : ", ($ENV{QS_CONTEXT_TARGET_PATH} // "(unset)"), "\n";
