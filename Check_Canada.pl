#!/usr/bin/perl -w

use strict;
use diagnostics;

my $Source=$ARGV[0];
#my $Source="/opt/log/atg/2014/03/13512/sm";
my @Files;
my $Verbose="F";
my $Loop; my $Tail;
my %Visited; 

my %Canada = (
#  204 => 'TestingSite',
  218 => 'Winnipeg',
  217 => 'Swift Current',
  198 => 'Calgary',
  214 => 'Kelowna',
  225 => 'Port Hardy',
  216 => 'Prince Rupert',
  226 => 'Greely',
  215 => 'Toronto',
  243 => 'Quebec',
  xxx => 'Strathroy',
  229 => 'International Falls',
  66 => 'Broadview',
  224 => 'Chapleau'
);

#print "Checking Sites:\n";
#foreach $Loop ( sort ( keys ( %Canada ) ) ) {
#  print "\$Canada{$Loop} :$Canada{$Loop}:\n";
#}

(undef, undef, undef ,undef, undef, undef, $Tail, undef)=split('/', $Source);

chdir($Source);

open(FILES, "ls -1 $Source | grep SM.tar.gz |");
while(<FILES>) {
  chomp;
  push(@Files, $_);
}


foreach $Loop (@Files) {
  open(INPUT, "/bin/tar xzvOf $Loop \"*_Airlink.txt\" 2>/dev/null |");
  while(<INPUT>) {
    chomp;
    next unless ( /SectorID, \d\d \d\d \d\d \d\d \d\d/ );
    #Serving_SectorID, 00 00 00 00 00 00 00 00 00 00 00 00 00 02 19 00 
    #Serving_SectorID, 00 00 00 00 00 00 00 00 00 00 00 00 00 00 08 00 
    #Serving_SectorID, 00 00 00 00 00 00 00 00 00 00 00 00 00 01 81 04 
    #Serving_SectorID, 00 00 00 00 00 00 00 00 00 00 00 00 00 00 27 04

    $_ =~ /Serving_SectorID, \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d (\d\d) (\d\d) (\d\d)/;
    my $Cell1=$1;
    my $Cell2=$2;
    my $Cell="$1"."$2";
    $Cell =~ s/^0+//;
    my $Sector=$3;
    #my $SectorLine = ", Cell $Cell, Sector $Sector";
    $Visited{$Cell}="Tail $Tail has used site $Cell - $Canada{$Cell}" if ( $Canada{$Cell} );
  }
}

foreach $Loop ( sort ( keys ( %Visited ) ) ) {
  print "$Visited{$Loop}\n";
}

