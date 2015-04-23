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
  print "Options: \n";
  print "  -e = Show Display known \"error related lines\"\n";
  print "  -t = Show Verbose Temperature Readings\"\n";
  print " --flightstates = Show changes in flight states\n";
  print " --auth = Show Authentication Status information\n";
  print " --time = Show time differences\n";
  print " --stats = Show ATG Stats/Versins\n";
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
my $AircardVersion="";
my $ATGVersion="";
my $Coverage="";
my $CoW="false";
my $CoWINIT="false";


if ( ! $opt_f ) {
#  print "You did not specify a -f <file>\n";
#  print "  Assuming you want to run on console.log in the currnet directory.\n";
  $opt_f="console.log";
}

my $PWD=$ENV{PWD};

$opt_f =~ /.*(\d\d\d\d\d)\.\d\d\d\d\-\d\d\-\d\d\-\d\d\-\d\d\-\d\d\.console/;
my $tail=$1;

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
#open(INPUT, "<$opt_f") || die "Can't open $opt_f :$?:\n";
open(INPUT, "$OpenCommand") || die "Can't open $opt_f :$?:\n";
while(<INPUT>) {
  chomp;
  $Line=$_;

  &Process_Coverage("$Line") if ( $Line =~ /ABS COVERAGE/);
  &Process_CellOnWheels("$Line") if ( $Line =~ /CellOnWheels=/);
  &Process_Flight_State("$Line") if ( $Line =~ /Flight State \=\=\=/);
  &Process_AircardVersion("$Line") if ( $Line =~ /Aircard Version:/ );
  &Process_ATGVersion("$Line") if ( $Line =~ /ATG Application Version/ );
  &Process_Signal_Strength("$Line") if (( $Line =~ /Signal Strength:/) && ( $ASA eq "T" ) && ( $Coverage eq "INSIDE ABS COVERAGE" ) );
  #&Process_Signal_Strength("$Line") if (( $Line =~ /Signal Strength:/) && ( $ASA eq "T" ) ); 
}

&Display_Stats if ( @Streaks );

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
  for $Loop ( 0..$#Streaks ) {
    $tail="manual" if ( ! $tail );
    print "$tail, $ATGVersion, $AircardVersion, $AircardType, ATG Init in CoW=$CoWINIT, $Streaks[$Loop]\n";
  }
#  print "\n";
}

sub Process_Signal_Strength {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.*Signal Strength: +(.*)$/;

#  print "\$StateLine :$StateLine:\n";
#  print "\$2 :$2: \$LastSINR :$LastSINR:\n" if ( $tail eq "13419");
  if ( ( $2 eq "-27.0" ) && ( $LastSINR eq "-27.0" ) ) {
    $LastSINRCount++;
  }


  if ( $LastSINR ne $2 ) {
    if (( $LastSINR eq "-27.0" ) && ( $LastSINRCount > $CountMin ) ) {
      push(@Streaks,"Just ended a streak of -27 $LastSINRCount times at $1");
    }
    $LastSINR="$2";
    $LastSINRCount=0;
  }
}

sub Process_AircardVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d.*Aircard Version: +(.*)/;

  my $Date="$1";

  $AircardVersion=$2;
  
}


sub Process_ATGVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d.*ATG Application Version +: +(.*)/;

  my $Date="$1";
  $ATGVersion=$2;
  
}


sub Process_Flight_State {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.*\> (.*)$/;
  if ( $2 eq "ABOVE_SERVICE_ALTITUDE" ) {
    $ASA="T";
  } else {
    $ASA="F";
  }
}


sub Process_Coverage {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) .* (\w+SIDE ABS COVERAGE)/;
  if ( $Coverage !~ $2 ) {
    $Coverage=$2;
    print "Pushing $1 -- $2\n" if ( $Verbose );
  }
}


sub Process_CellOnWheels {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d).*CellOnWheels=(\w+).*/;

  my $Date=$1;
  $CoW=$2;

  if ( $StateLine =~ /System Configurations being initialised/ ) {
    $CoWINIT="true";
  }
}


