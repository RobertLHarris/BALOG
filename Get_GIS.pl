#!/usr/bin/perl -w

use strict;
use diagnostics;
use Date::Calc qw(:all);
use Date::Manip;

# GetOpt
use vars qw( $opt_h $opt_v $opt_f $opt_t );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v f=s t ");

#
if ( $opt_h ) {
  print "\n\n";
  print "Usage:  Messages.pl <options> -f <Log_File>\n";
  print " -h = help (This screen)\n";
  print "\n";
  print "Required: \n";
  print " -f <Log_File> : Specify a console log to read.\n";
  print "\n";
  print "Options: \n";
  print "  -t = Use TechSupport airlink-<user>.log\n";
  print "\n\n\n";
  exit 0;
}
my $Finish;



#
# Declare Variables
#
#
my $Verbose=$opt_v;
#
my $User=$ENV{"LOGNAME"};
#
my $BlessedATG="2.1.2";
my $MaxTemp=0;  my $MaxSafeTemp=55; my $MaxTempString=""; my $TempErrors;
#
my $Line;
my $Loop;my $Date;
# Data Collection
my %Lat; my %Lon; my %Alt; my %DRC;

#
if ( $opt_t ) {
  $opt_f="/tmp/airlink-".$User.".log";
} 

if ( ! $opt_f ) {
  print "You did not specify a -f <file>\n";
  print "  Tell me what to process!\n";
  exit 0;
}


open(INPUT, "<$opt_f") || die "Can't open $opt_f :$?:\n";
while(<INPUT>) {
  chomp;
  $Line=$_;

  &Process_Coverage("$Line") if ( $Line =~ /^\d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d/ );
  &Process_DRC("$Line") if ( $Line =~ /^DRC_BUFFER,/);


#  &Process_Coverage("$Line") if ( $Line =~ /ABS COVERAGE/);
}

&Display_Data;

# Nothing to see below here, move along citizen. 
exit 0;




#################
# Sub Procs Here #
##################
sub Display_Data {
  my $Key;

  print "\n";
  foreach $Key ( sort ( keys ( %Lat ) ) ) {
    print "$Key, $Lat{$Key}, $Lon{$Key}, $Alt{$Key}, $DRC{$Key}\n";
  }
  print "\n";
}


sub Process_Coverage {
  my $StateLine=$_[0];
  print "\$StateLine :$StateLine:\n" if ( $opt_v );
  #2014-03-01 00:41:23,38.59,-104.54,5153

  $StateLine =~ /^(\d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d),(-*\d+\.\d+),(-*\d+\.\d+),(.*)/;
  $Date=$1;
  my $Lat=$2;
  my $Lon=$3;
  my $Alt=$4;
  print "\$Date :$Date:\n" if ( $opt_v );
  print "\$Lat :$Lat:\n" if ( $opt_v );
  print "\$Lon :$Lon:\n" if ( $opt_v );
  print "\$Alt :$Alt:\n" if ( $opt_v );

  $Lat{$Date}=$Lat;
  $Lon{$Date}=$Lon;
  $Alt{$Date}=$Alt;
}


sub Process_DRC {
  my $StateLine=$_[0];
  print "\$StateLine :$StateLine:\n" if ( $opt_v );
  #2014-03-01 00:41:23,38.59,-104.54,5153

  $StateLine =~ /^DRC_BUFFER, (.*)/;
  my $DRC=$1;

  print "\$DRC :$DRC:\n" if ( $opt_v );

  $DRC{$Date}=$DRC;
}


