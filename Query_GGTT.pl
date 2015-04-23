#!/usr/bin/perl -w

use strict;
use diagnostics;

# Lets get our DB connection
use DBI;
# sqlplus64 GTT_RO/GTT_RO123@//pilclust02-scan.aircell.prod/prdstrm1_service.aircell.prod
my $SQLUser="GTT_RO";
my $SQLPassword="GTT_RO123";
my $SQLHost="pilclust02-scan.aircell.prod";
my $SQLService="prdstrm1_service.aircell.prod";


# GetOpt
use vars qw( $opt_h $opt_v $opt_p $opt_g $opt_sipro $opt_history );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v p=s g=s sipro history ");

my $Verbose=$opt_v;

&Show_Usage if ( $opt_h );

my $Loop;
my @data;
my $sth;
my $Phone;
my $GDID;

print "\n";
print "Establishing a connection: " if ( $Verbose );

my $dbh = DBI->connect('dbi:Oracle:',"$SQLUser\@$SQLHost/$SQLService","$SQLPassword") || die "Couldn't connect to DB :$?:\n";
#my $sth=$dbh->prepare("desc p1psg_app.gtt_log;") || die "$?";

print "Connected.\n" if ( $Verbose );

$Phone=$opt_p if ( $opt_p );
$Phone=$opt_g if ( $opt_g );
&Process_Phone_Details("$Phone") if ( ( $Phone ) && ( $opt_p ) );
&Process_GDID_Details("$Phone") if ( ( $Phone ) && ( $opt_g ) );
&Count_SIPRO if ( $opt_sipro );

# Close our DB Connection
$sth->finish();

exit 0;

########################
# Sub Procs Below Here #
########################
sub Show_Usage {
  print "\n\n";
  print "Usage:  query_gtt.pl <options> <Command>\n"; 
  print "Command: \n";
  print " -h = help (This screen)\n";
  print " -p <PHONE #> = Show Accuroam GTT Phone Data\n";
  print " -g <PHONE GDID> = Show Accuroam GTT Phone Data\n";
  print "\n";
  print "Options: \n";
  print " --history = Show SIPID/GDID history for a phone\n";
  print " --sipro = Show unique #'s for SIPRO licenses.\n";
  print "  -v  = Verbose output\n";
  print "\n\n\n";
  exit 0;
}

sub Sanitize_Phone {
  $Phone=$_[0];
  $Phone =~ s/[\-\.\ ]//g;
#  $Phone="1".$Phone if ( $Phone !~ /^1/ );
  return($Phone);
}


sub Process_Phone_Details {
  my $InputPhone=$_[0];
  my $Query;
  my @PhoneData;
  my @PhoneActivity;
  $Phone=&Sanitize_Phone("$InputPhone");


  # Without History
  # They broke this query, re-using txn_id
  #$Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.ls_user_phone like '%$Phone%' and l.txn_id in ( select max(txn_id) from p1psg_app.gtt_log t where t.ls_user_phone = l.ls_user_phone ) order by ID";
  # Use last CREATED_DAte instead
  $Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.ls_user_phone like '%$Phone%' and l.CREATED_DATE in ( select max(CREATED_DATE) from p1psg_app.gtt_log t where t.ls_user_phone = l.ls_user_phone ) order by ID";
  # With
  $Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.ls_user_phone like '%$Phone%' order by ID" if ( $opt_history );
  $Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.ls_user_phone like '%$Phone%' order by ID" if ( $opt_history );
  print "\$Query :$Query:\n" if ( $Verbose );
  $sth=$dbh->prepare("$Query") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  while ( my @data = $sth->fetchrow_array()) {
    undef(@PhoneData);
    foreach $Loop (0..$#data) {
      print "\@data[$Loop] :$data[$Loop]:\n" if ( ( $Verbose ) && ( $data[4] ) );
      push(@PhoneData, $data[$Loop]);
    }
    if ( $#PhoneData > -1 ) {
      $PhoneData[1]="Undefined" if ( ! $PhoneData[1] );
      $PhoneData[3]="Undefined" if ( ! $PhoneData[3] );
      $PhoneData[4]="Undefined" if ( ! $PhoneData[4] );
      $data[6]="ERROR" if ( ! $data[6] );
      print "Information for $Phone:\n";
      print "  Accuroam ID   $PhoneData[0]\n";
      print "  MSISDN        $PhoneData[1]\n";
      print "  SIPID/GDID    $PhoneData[2]\n";
      print "  Carrier       $PhoneData[3]\n";
      print "  Net Type      $PhoneData[4]\n" if ( $PhoneData[4] );
      print "  Created Date  $PhoneData[5]\n";
      print "  Updated Date  $PhoneData[6]\n";
      $GDID=$PhoneData[2];
    } else {
      print "No registration entry found for phone $Phone\n";
      print "\n\n";
      exit 0;
    } 

    # Lets see if we can get some activity data
    $Query="select TXN_ID, TXN_START_TIME, XML_DATA from accuroam_activity where GDID='$GDID' and TXN_ID = ( select max(TXN_ID) from accuroam_activity where GDID='$GDID' ) order by ID";
    my $sth2=$dbh->prepare("$Query") || die "$?";
    $sth2->execute() || die "$?" or die "Couldn't execute statement: " . $sth2->errstr;
  
    my $Activity=0;
    while ( my @data = $sth2->fetchrow_array()) {
      foreach $Loop (0..$#data) {
        print "\@data[$Loop] :$data[$Loop]:\n" if ( ( $Verbose ) && ( $data[4] ) );
      }
      if ( $#data > -1 ) {
        $Activity=1;
        print "\n";
        print "  Last Activity for $GDID:\n";
        print "    TXN_ID        $data[0]\n";
        print "    DATE          $data[1]\n";
        print "    XMS Data      $data[2]\n" if ( $data[2]);
        print "\n";
      } 
    }
    if ( $Activity == 0 ) {
      print "\n";
      print "  ** No Activity found for $GDID\n";
      print "\n";
    }
  }

  if ( ! $GDID ){
    print "No registration entry found for phone $Phone\n";
    print "\n\n";
    exit 0;
  }
}


sub Process_GDID_Details {
  my $InputPhone=$_[0];
  my $Query;
  my @PhoneData;
  my @PhoneActivity;
#  $Phone=&Sanitize_Phone("$InputPhone");


  # Without History
  # They broke this query, re-using txn_id
  #$Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.GDID like '%$Phone%' and l.txn_id in ( select max(txn_id) from p1psg_app.gtt_log t where t.GDID = l.GDID ) order by ID";
  # Use last CREATED_DAte instead
  $Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.GDID like '%$Phone%' and l.CREATED_DATE in ( select max(CREATED_DATE) from p1psg_app.gtt_log t where t.GDID = l.GDID ) order by ID";
  # With
  $Query="select ID, SMS_USER_PHONE, GDID, SMS_CARRIER_CONTACT, NETWORK_TYPE, CREATED_DATE, UPDATED_DATE from p1psg_app.gtt_log l where l.GDID like '%$Phone%' order by ID" if ( $opt_history );
  print "\$Query :$Query:\n" if ( $Verbose );
  $sth=$dbh->prepare("$Query") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  while ( my @data = $sth->fetchrow_array()) {
    undef(@PhoneData);
    foreach $Loop (0..$#data) {
      print "\@data[$Loop] :$data[$Loop]:\n" if ( ( $Verbose ) && ( $data[4] ) );
      push(@PhoneData, $data[$Loop]);
    }
    if ( $#PhoneData > -1 ) {
      $data[6]="ERROR" if ( ! $data[6] );
      print "Information for $Phone:\n";
      print "  Accuroam ID   $PhoneData[0]\n";
      print "  MSISDN        $PhoneData[1]\n";
      print "  SIPID/GDID    $PhoneData[2]\n";
      print "  Carrier       $PhoneData[3]\n";
      print "  Net Type      $PhoneData[4]\n" if ( $PhoneData[4] );
      print "  Created Date  $PhoneData[5]\n";
      print "  Updated Date  $PhoneData[6]\n";
      $GDID=$PhoneData[2];
    } else {
      print "No registration entry found for phone $Phone\n";
      print "\n\n";
      exit 0;
    } 

    # Lets see if we can get some activity data
    $Query="select TXN_ID, TXN_START_TIME, XML_DATA from accuroam_activity where GDID='$GDID' and TXN_ID = ( select max(TXN_ID) from accuroam_activity where GDID='$GDID' ) order by ID";
    my $sth2=$dbh->prepare("$Query") || die "$?";
    $sth2->execute() || die "$?" or die "Couldn't execute statement: " . $sth2->errstr;
  
    my $Activity=0;
    while ( my @data = $sth2->fetchrow_array()) {
      foreach $Loop (0..$#data) {
        print "\@data[$Loop] :$data[$Loop]:\n" if ( ( $Verbose ) && ( $data[4] ) );
      }
      if ( $#data > -1 ) {
        $Activity=1;
        print "\n";
        print "  Last Activity for $GDID:\n";
        print "    TXN_ID        $data[0]\n";
        print "    DATE          $data[1]\n";
        print "    XMS Data      $data[2]\n";
        print "\n";
      } 
    }
    if ( $Activity == 0 ) {
      print "\n";
      print "  ** No Activity found for $GDID\n";
      print "\n";
    }
  }

  if ( ! $GDID ){
    print "No registration entry found for phone $Phone\n";
    print "\n\n";
    exit 0;
  }
}













sub Count_SIPRO {

  $sth=$dbh->prepare("SELECT COUNT(GDID) FROM gtt_log") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  while ( my @data = $sth->fetchrow_array()) {
    foreach $Loop (0..$#data) {
      print "\@data[$Loop] :$data[$Loop]:\n" if ( $Verbose );
    }
  }
}


