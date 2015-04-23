#!/usr/bin/perl -w
$|=1;

use strict;
use diagnostics;

# Lets get our DB connection
use DBI;
#
# sqlplus64 GGP_RO/GGP_RO123@//pilclust02-scan.aircell.prod/prdstrm2_service.aircell.prod
my $SQLUser="GGP_RO";
my $SQLPassword="GGP_RO123";
my $SQLHost="pilclust02-scan.aircell.prod";
#my $SQLHost="10.241.108.85";
my $SQLService="prdstrm2_service.aircell.prod";


# Oracle query Info
#  - SELECT owner, table_name from all_tables
#  - desc ba_vision_accounting
#
#  - select distinct ( KEY_GENERATION_STATUS ) from ba_vision_accounting;      
#  - KEY_GENERATION_STATUS = result of the DRM check
#    - 1 = good
#    - Anything else is bad
#    - 10 = region code failure
#
#  - Event_type
#   - play is the free 30 second preview
#   - view is the view after play (preview)
#   - playview is the outright play, no preview
#
# - REQUEST_TYPE - Test value, ignore
#



# GetOpt
use vars qw( $opt_h $opt_v $opt_drm $opt_drmfail $opt_A $opt_D $opt_sbb $opt_cmd );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v drm drmfail A=s D=s sbb cmd ");

if ( $opt_h ) {
  &Show_Usage;
  exit 0;
}

my $Loop;
my @data;
my $sth;

my $Date=$opt_D if ( $opt_D );
if ( ! $Date ) {
  print "You didn't specify a date, using todays.\n";
  chomp ( $Date=`/bin/date +%d-%b-%y` );
}

# (format is dd-mm-yy hh:mm:ss am/pm)
if ( $Date !~ /^\d\d\-\w\w\w\-\d\d/ ) {
  print "Date MUST be in the format of dd-mmm-yy hh:mm:ss am/pm\n";
  print "  13-MAR-14 12:00:00 AM\n";
  print "  * Time portion is optional\n";
  exit 0;
}

print "\n";
print "Establishing a connection: ";

if ( $opt_cmd ) {
  print " Connection Command: \n";
  print " connect('dbi:Oracle:',\"$SQLUser\@$SQLHost/$SQLService\",\"$SQLPassword\")\n";
  print "\n";
}
my $dbh = DBI->connect('dbi:Oracle:',"$SQLUser\@$SQLHost/$SQLService","$SQLPassword") || die "Couldn't connect to DB :$?:\n";

print "Connected.\n";

&Check_DRM if ( $opt_drm );
&Check_DRM_FAILS if ( $opt_drmfail );
&Check_INMARSAT if ( $opt_sbb );



exit 0;

########################
# Sub Procs Below Here #
########################
sub Show_Usage {
  print "\n\n";
  print "Usage:  query_gtt.pl <options> <Command>\n"; 
  print "Command: \n";
  print " -h = help (This screen)\n";
  print " --drm = Show the status of DRM checks.\n";
  print " --drmfail = Show the status of DRM checks.\n";
  print " --sbb = Show the Inmarsat notifications.\n";
  print " --cmd = Show the database commands given.\n";
  print "   Requires -D <date>\n";
  print "\n";
  print "Required: \n";
  print " -D <Date> : Specify a date to query.\n";
  print "     Date format is (format is dd-mmm-yy hh:mm:ss am/pm)\n";
  print "\n";
  print "Options: \n";
  print "  -v  = Verbose output\n";
  print "\n\n\n";
  exit 0;
}


sub Check_DRM {
  my $Proceed="F";
  my $Success="";

  if ( $Date ) {
    $Proceed="T";
  }

  if ( $Proceed eq "F" ) {
    print "Not enough qualifiers, you might damage the system.  Please use --date  to limit.\n";
    exit 0;
  }

  print "\$opt_A :$opt_A:\n" if ( $opt_A );
  my $QueryString="select DATE_TIME, MEDIA_TITLE, KEY_GENERATION_TIME, KEY_GENERATION_STATUS, ACID, EVENT_TYPE from ba_vision_accounting";
  $QueryString=$QueryString." where date_time>'$Date'" if ( $Date );
  $QueryString=$QueryString." and ACID = '$opt_A'" if ( $opt_A );
  $QueryString=$QueryString." order by DATE_TIME" if ( $Date );

  print "\$QueryString :$QueryString:\n" if ( $opt_cmd );

  $sth=$dbh->prepare("$QueryString") || die "$?"; 
  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  while ( my @data = $sth->fetchrow_array()) {
    # Skip types that are not "PLAY" or "PREVIEW"
    next unless (( $data[5] eq "PLAY" ) || ( $data[5] eq "PREVIEW" ));
    foreach $Loop (0..$#data) {
      print "\@data[$Loop] :$data[$Loop]:\n" if ( $opt_v );
    }
    # Per Thomas Glaess
    if ( $data[3] == 1 ) {
      $Success="SUCCESSFULLY ( $data[3] )";
    } else {
      $Success="FAIL ( $data[3] )";
    }
    $data[0] =~ s/0+ ([AP]M)$/ $1/;
    # Bug with a missing movie title?
    $data[1]="Unknown" if ( ! $data[1] );
    print "$data[0], ACID $data[4] took $data[2] miliseconds to $Success to get the DRM key to $data[5] $data[1]\n";
  }
  # Close our DB Connection
  $sth->finish();
}


sub Check_DRM_FAILS {
  my $Proceed="F";
  my $Success="";

  my $QueryString="select DATE_TIME, MEDIA_TITLE, KEY_GENERATION_TIME, KEY_GENERATION_STATUS, ACID, EVENT_TYPE from ba_vision_accounting where KEY_GENERATION_STATUS !=1";
  $QueryString=$QueryString." and date_time>'$Date'";
  $QueryString=$QueryString." order by DATE_TIME" if ( $Date );

  print "\$QueryString :$QueryString:\n" if ( $opt_cmd );

  $sth=$dbh->prepare("$QueryString") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  while ( my @data = $sth->fetchrow_array()) {
    # Skip types that are not "PLAY" or "PREVIEW"
    next unless (( $data[5] eq "PLAY" ) || ( $data[5] eq "PREVIEW" ));
    foreach $Loop (0..$#data) {
      print "\@data[$Loop] :$data[$Loop]:\n" if ( $opt_v );
    }
    if ( $data[3] == 1 ) {
      $Success="SUCCESSFULLY";
    } else {
      $Success="FAIL";
    }
    $data[0] =~ s/0+ ([AP]M)$/ $1/;
    # Bug with a missing movie title?
    $data[1]="Unknown" if ( ! $data[1] );
    print "$data[0], ACID $data[4] took $data[2] miliseconds to $Success to get the DRM key to $data[5] $data[1]\n";
  }
  # Close our DB Connection
  $sth->finish();
}




sub Check_INMARSAT {

  if ( ! $Date ) {
    print "Please specify a date.  ( DD-MMM-YY ).\n";
    print "  If you are looking for verification of connection, use \"-D 02-Feb-14\" as a known value.\n";
    exit 0;
  }
  my $QueryString="select * from notifications where notification_type=1 ";
  $QueryString=$QueryString." and created_date>'$Date'" if ( $Date );
  $QueryString=$QueryString." order by created_date" if ( $Date );

  print "\$QueryString :$QueryString:\n" if ( $opt_cmd );

  $sth=$dbh->prepare("$QueryString") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  while ( my @data = $sth->fetchrow_array()) {
    foreach $Loop (0..$#data) {
      print "\@data[$Loop] :$data[$Loop]:\n" if ( $opt_v );
    }
    $data[2] =~ /.* : .* (\d+) \d\d:\d\d .*/;
    my $Incident=$1;
    print "Inmarsat Notification: $data[2]\n";
    print "  Incident ( $Incident ) :  Created: $data[8], Expired: $data[9], Started: $data[11]\n";
    print "\n";
  }
  # Close our DB Connection
  $sth->finish();
}




