#!/usr/bin/perl -w

use strict;
use diagnostics;

use vars qw ( $opt_h $opt_v $opt_f $opt_T $opt_t $opt_nocomp );
use Getopt::Mixed;
Getopt::Mixed::getOptions(" b v f=s T=s t nocomp ");

# Define Variables
#
# Generic Working Variables
my $Line;
my $Loop;
#
# Output File
my $Target;
#
# Aircraft identifiers
my $Tail;
my $Acid;
#
# Flight Data
my $SINR;
my $DRC;
my $LAT;
my $LON;
my $HVel;
my $VVel;
my $GTime;
#
# Drift Compensation
my $HaveDrift=0;
my $ShortDrift=0;
my $ShortDriftLast=1;
#
my $Year; my $Mon; my $Day; my $Hour; my $Min; my $Sec; my $Mili;
my $year; my $month; my $day; my  $hour; my $min; my $sec;


