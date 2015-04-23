#!/usr/bin/perl -w

use strict;
use diagnostics;

my $Verbose="F";
my $Source=$ARGV[0];
my $AuthError="F";
my @Errors; my $Errors;
#
my $Content; my $Tmp;


open(INPUT, "/usr/bin/zgrep -a \"Authentication Message response  5\" $Source |");
while(<INPUT>) {
  chomp;
#  print "\$_ :$_:\n";
  push(@Errors, $_);
}

if ($#Errors >= 0) {
  $Errors=$#Errors+1;
  print "Found ".$Errors." errors in $Source\n";
}
