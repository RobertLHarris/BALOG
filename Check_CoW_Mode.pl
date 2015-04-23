#!/usr/bin/perl -w
$| = 1;

use strict;
use diagnostics;
use Date::Calc qw(:all);

# GetOpt
use vars qw( $opt_h $opt_v $opt_f $opt_all $opt_e $opt_t $opt_flightstates $opt_time $opt_auth $opt_stats );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v f=s e t all flightstates time auth stats ");


# Make it easier
if ( $opt_all ) {
  $opt_e=1;
  $opt_flightstates=1;
  $opt_time=1;
  $opt_auth=1;
  $opt_stats=1;
}


if ( $opt_h ) {
  print "\n\n";
  print "Usage:  atg.pl <options> -f <Log_File>\n";
  print " -h = help (This screen)\n";
  print "\n";
  print "Required: \n";
  print " -f <Log_File> : Specify a console log to read.\n";
  print "\n";
  print "\n\n\n";
  exit 0;
}


#
# Declare Variables
#
#
my $Verbose=$opt_v;
#
#my $CountMin="8";
my $CountMin="30";
my $Line;
my $ASA="F";
my @SINR; 
my $LastSINR="";
my $LastSINRCount="";
my $OpenCommand;
my @Streaks;
my $Loop;
my $ACID;
my $AircardVersion="";
my $ATGVersion="";
my $Coverage="";
my $CoW="false";
my $CoWINIT="false";


if ( ! $opt_f ) {
  $opt_f="console.log";
}

my $PWD=$ENV{PWD};

$opt_f =~ /.*(\d\d\d\d\d)\.\d\d\d\d\-\d\d\-\d\d\-\d\d\-\d\d\-\d\d\.console/;
my $tail=$1;

$tail="manual" if ( ! $tail );

#
# What kind of file are we opening?
# 
if ( ( $opt_f =~ /\.tar.gz$/ ) || ( $opt_f =~ /\.tgz$/ )) {
  print "Opening Tar-GZ\n" if ( $opt_v ); 
  $OpenCommand="tar xzvOf $opt_f 2>/dev/null |";
} elsif ( $opt_f =~ /\.gz/ ) {
  print "Opening Compressed\n" if ( $opt_v ); 
  $OpenCommand="/bin/gunzip -c $opt_f |";
} elsif ( $opt_f =~ /\*$/ ) {
  print "Opening Many Compressed\n" if ( $opt_v ); 
  $OpenCommand="/bin/gunzip -c $opt_f |";
} else {
  print "Opening Un-compressed\n" if ( $opt_v ); 
  $OpenCommand="<$opt_f";
}

open(INPUT, "$OpenCommand") || die "Can't open $opt_f :$?:\n";
while(<INPUT>) {
  chomp;
  $Line=$_;

  &Process_ACID("$Line") if ( $Line =~ /acidValFromACID/);
  &Process_CellOnWheels("$Line") if ( $Line =~ /CellOnWheels=true/);
  &Process_AircardVersion("$Line") if ( $Line =~ /Aircard Version:/ );
  &Process_ATGVersion("$Line") if ( $Line =~ /ATG Application Version/ );
}

&Display_Stats if ( $CoWINIT eq "true" );;

##################
# Sub Procs Here #
##################


sub Display_Stats {
  my $AircardType;
  if ( $AircardVersion =~ /Bigsky/ ) {
    $AircardType="Type: Rev-A"
  } elsif ( $AircardVersion =~ /Aircard2/ ) {
    $AircardType="Type: Rev-B"
  } else {
    $AircardType="Type: Unknown"
  }
  print "$tail, $ACID, $ATGVersion, $AircardVersion, $AircardType, ATG Init in CoW=$CoWINIT\n";
#  print "\n";
}

sub Process_AircardVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d.*Aircard Version: +(.*)/;

  my $Date="$1";

  $AircardVersion=$2;
  
}


sub Process_ACID {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d.* ACM MAC Address: acidValFromACID : +(.*)/;

  $ACID=$2;
  
}


sub Process_ATGVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d.*ATG Application Version +: +(.*)/;

  my $Date="$1";
  $ATGVersion=$2;
  
}


sub Process_CellOnWheels {
  my $StateLine=$_[0];

  if ( $StateLine =~ /System Configurations being initialised/ ) {
    $CoWINIT="true";
  }
}


