#!/usr/bin/perl -w
$| = 1;

use strict;
use diagnostics;
use Date::Calc qw(:all);

# GetOpt
use vars qw( $opt_h $opt_v $opt_f $opt_all $opt_e $opt_T $opt_m $opt_y $opt_t $opt_flightstates $opt_time $opt_auth $opt_stats );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v f=s e T=s m=s y=s t all flightstates time auth stats ");


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
  print "Usage:  Check_ACM_Fail.pl <options> -f <Log_File>\n";
  print " -h = help (This screen)\n";
  print "\n";
  print "Required: \n";
  print " -f <Log_File> : Specify a console log to read.\n";
  print " -T <Tail> : Specify a Tail Check.\n";
  print "  ** This requires -m and -y\n";
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
my $ACMFail="false";
my $Mon;
my $Year;
my @Files;
my $Files;
my $File;


my $PWD=$ENV{PWD};

$File=$opt_f if ( $opt_f );
$File =~ /.*(\d\d\d\d\d)\.\d\d\d\d\-\d\d\-\d\d\-\d\d\-\d\d\-\d\d\.console/ if ( $opt_f );
my $tail=$1;

$tail="manual" if ( ! $tail );

if ( $opt_T ) {
  $tail=$opt_T;
  if ( ( ! $opt_m ) || ( ! $opt_y ) ) {
    print "\n";
    print "  You specified -T, -m and -y are required\n";
    print "\n";
    exit 1;
  }
  $Mon=$opt_m; $Mon=substr("0"."$Mon", -2);
  $Year=$opt_y; $Year=substr("20"."$Year", -4);

  my $Path="/opt/log/atg/".$Year."/".$Mon."/".$tail."/abs_logs/acpu_java/*console*";

  open(INPUT, "ls -1 $Path |");
  while(<INPUT>) {
    chomp;
    push(@Files, $_);
  }
}

$File=$opt_f if ( $opt_f );

if (( ! $File ) && ( ! @Files )) {
  $File="console.log";
}


#
# What kind of file are we opening?
# 
if ( ! $opt_T ) {
  if ( ( $File =~ /\.tar.gz$/ ) || ( $File =~ /\.tgz$/ )) {
    print "Opening Tar-GZ\n" if ( $opt_v ); 
    $OpenCommand="tar xzvOf $File 2>/dev/null |";
  } elsif ( $File =~ /\.gz/ ) {
    print "Opening Compressed\n" if ( $opt_v ); 
    $OpenCommand="/bin/gunzip -c $File |";
  } elsif ( $File =~ /\*$/ ) {
    print "Opening Many Compressed\n" if ( $opt_v ); 
    $OpenCommand="/bin/gunzip -c $File |";
  } else {
    print "Opening Un-compressed\n" if ( $opt_v ); 
    $OpenCommand="<$File";
  }
}

print "\$File :$File:\n" if ( $Verbose );
print "\$OpenCommand :$OpenCommand:\n" if ( $Verbose );

if ( $opt_T ) {
  foreach $File ( @Files ) {
    $OpenCommand="/bin/gunzip -c $File | tar xvOf - 2>/dev/null |";
    open(INPUT, "$OpenCommand") || die "Can't open $File :$?:\n";
    while(<INPUT>) {
      chomp;
      $Line=$_;
      print "\$_ :$_:\n" if ( $Verbose );
      &Process_Line($Line);
    }
    close(INPUT);
  }
} else {
  open(INPUT, "$OpenCommand") || die "Can't open $File :$?:\n";
  while(<INPUT>) {
    chomp;
    $Line=$_;
    print "\$_ :$_:\n" if ( $Verbose );
    &Process_Line($Line);
  }
}

&Display_Stats if ( $ACMFail eq "true" );;

##################
# Sub Procs Here #
##################

sub Process_Line {
  my $Line=$_[0];

  $ACMFail="true" if ( $Line =~ /SW_KEYS: AbsControlServiceImpl: uploadKeysAMFDataToACM\(\): uploadKeysAMFFile : FALSE/);
  &Process_ACID("$Line") if ( $Line =~ /acidValFromACID/);
  &Process_AircardVersion("$Line") if ( $Line =~ /Aircard Version:/ );
  &Process_ATGVersion("$Line") if ( $Line =~ /ATG Application Version/ );
}

sub Display_Stats {
  my $AircardType;
  if ( $AircardVersion =~ /Bigsky/ ) {
    $AircardType="Type: Rev-A"
  } elsif ( $AircardVersion =~ /Aircard2/ ) {
    $AircardType="Type: Rev-B"
  } else {
    $AircardType="Type: Unknown"
  }
  print "$tail, $ACID, $ATGVersion, $AircardVersion, $AircardType, ATG ACM Fail=$ACMFail\n";
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
