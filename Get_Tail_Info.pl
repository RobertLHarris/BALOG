#!/usr/bin/perl -w

use strict;

my $Tail_File="BA_tailVerReport_2014-09-17.csv";
my $NJ_File="NJ Tails for Escalation_v2.csv";
my $OUTText="NetJets.txt";
my $OUTCSV="NetJets.csv";

open(OUTText, ">$OUTText");
open(OUTCSV, ">$OUTCSV");

open(NJINPUT,"<$NJ_File");
while(<NJINPUT>) {
  chomp;
  my ( $ATGSN, $Tail, $Last_Flight, $Aircraft )=split(',', $_);
  next if ( $Tail =~ /undefined/i );
#  print "\$_ :$_:\n";

  #Serial #, ACPU_Ver, ATG_App_Ver, ATG_Config_Ver, Aircard_Ver, ACPU_Reboot_Time, First_Timestamp, Last_Timestamp, ACPU_Time_AT_GPS, GPS_TIME, ACID
  open(TAILINPUT, "/bin/grep $ATGSN $Tail_File |");
  while(<TAILINPUT>) {
    chomp;
    next if ( $_ !~ /^$ATGSN/ );
  #  print "2\$_ :$_:\n";
    my @ATG=split(',', $_);
    my $ATGVer=$ATG[2];
    my $Aircard=$ATG[4];
    my $AircardRev;
    if ( $Aircard =~ /^Bigsky/ ) {
      $AircardRev="Rev-A";
    } elsif ( $Aircard =~ /^Aircard2/ ) {
      $AircardRev="Rev-B";
    } else {
      $AircardRev="undefined";
    }
    my $ACID=$ATG[10];
    $ACID="Undefined" if ( ! $ACID );
   

    print OUTText " ATG Serial Number :$ATGSN\n";
    print OUTText "  Software Version :$ATGVer\n";
#    print OUTText "  Aircard Version :$Aircard\n";
    print OUTText "  Aircard Revision :$AircardRev\n";
    print OUTText "              ACID :$ACID\n";
    print OUTText "              Tail :$Tail\n";
    print OUTText "       Last Flight :$Last_Flight\n";
    print OUTText "     Aircraft Type :$Aircraft\n";
    print OUTText "\n\n";

#    print OUTCSV "$ATGSN,$ATGVer,$Aircard,$Aircard,$ACID,$Tail,$Last_Flight,$Aircraft\n";
    print OUTCSV "$ATGSN,$ATGVer,$AircardRev,$ACID,$Tail,$Last_Flight,$Aircraft\n";
  }
}

close(OUTText);
close(OUTCSV);
