#!/usr/bin/perl -w

use strict;
use diagnostics;

open(OUTPUT, ">/usr/local/bin/GGTT/GGTT_Licenses.txt");

open(INPUT, "echo \"select distinct acid, effective_start_date, effective_end_date from [TARGET_REPORTING].[dbo].[DIM_LICENSE_KEYS] l where l.item_nbr = 'P16637-101' and l.aircraft_reg_nbr <> 'NTSLAB'\" | isql -q GGTTPROD NETOPS_USR_RO Up5!w0N# |");
while(<INPUT>) {
  chomp;
  next unless ( /\| \w\w\w\w\w\w.* /);
  next if ( /\|\s*Connected/);
  next if ( /\| acid /);

  $_ =~ /\| (\w+) *\| (\d\d\d\d\-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d)\| (\d\d\d\d\-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d)\|/; 
 
  my $ACID=$1;
  my $Start=$2;
  my $Finish=$3; 
#  print "\$_ :$_:\n";
#  print "\$ACID :$ACID:\n";
  print OUTPUT "$ACID\t$Start\t$Finish\n";
  


}
close(INPUT);
close(OUTPUT);
