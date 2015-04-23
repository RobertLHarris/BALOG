#!/usr/bin/perl -w
$|=1;

use strict;
use diagnostics;

use Date::Calc qw(:all);
use Date::Manip;
use Class::Date;
use DBI;

# We need to exit gracefully including untieing our hash
$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;

# GetOpt
use vars qw( $opt_h $opt_v $opt_f $opt_T $opt_S $opt_P $opt_B $opt_D );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v f=s T=s S P B D");

if ( ( ! $opt_S ) && ( ! $opt_P ) ) {
  print "\n\n";
  print "You must choose a target DB.  SIT (-S) and/or PROT (-P)\n";
  print "You may use -B to specify both.\n";
  print "\n\n";
  exit 0;
}

if ( $opt_B ) {
  $opt_S=1;
#  $opt_P=1;
}

if ( $opt_h ) {
  print "\n\n";
  print "Usage:  EDW_Dump.pl <options> -f <Log_File>\n";
  print " -h = help (This screen)\n";
  print "\n";
  print "Required: \n";
  print " -f <Log_File> : Specify a console log to read.\n";
  print " -S : Upload data to SIT\n";
  print " -P : Upload data to PROD\n";
  print " -D : DryRun.  Testing only.  No actual work.\n";
  print " -B : Upload data to Both SIT and PROD\n";
  print "Optional: \n";
  print " -T <Tail> : Specify a what tail is being processed.\n";
  print "\n";
  exit 0;
}

#
# Declare Variables
#
#
my $Verbose=$opt_v;
#my $Verbose=1;
#
my $Date=`/bin/date +%Y%m%d%H%M%S`; chomp $Date;
my $TargetDir="/opt/log/EDW_Dumps";
my $LockFile="/tmp/EDW_Dump-Lockfile.touch";
my $Locked=1;
my $LockSleep=60;

#
my $Line;
my $Tail;
my $Loop;
my @Loop;
$Tail=$opt_T if ( $opt_T );
my @Output;
my $TimeStamp;
my $Insert;
my $GPS_LAT="LAT_Unknown"; my $GPS_LAT_go=0;
my $GPS_LON="LON_Unknown"; my $GPS_LON_go=0;
my $GPS_ALT="ALT_Unknown"; my $GPS_ALT_go=0;
my $GPS_HOR_VEL="HVEL_Unknown"; my $GPS_HOR_VEL_go=0;
my $GPS_VER_VEL="VVEL_Unknown"; my $GPS_VER_VEL_go=0;
my $GPS_TIME="TIME_Unknown"; my $GPS_TIME_go=0;
my $GPS_AGL;
my $GPS_DATA;
my $Key;
my $Value;
my $Event; # Used for cleaning up Variable conversions
#
#
my $User=$ENV{"LOGNAME"};

my $StartConsole=0;

open(INPUT, "<$opt_f") || die "Couldn't open input file $opt_f $!\n";
while(<INPUT>) {
  chomp;
  $_ =~ s/ +$//g;
  $GPS_DATA="$GPS_ALT, $GPS_LAT, $GPS_LON, $GPS_HOR_VEL, $GPS_VER_VEL";

  if ( ( ! $StartConsole ) && ( /Console: - / ) ) {
    $StartConsole=1;
  }

  print "Processing :$_:\n" if ( $Verbose );
  next if ( ! $StartConsole );

  print "Processing :$_:\n" if ( $Verbose );

  #
  # Process GPS lines
  #
  &Process_GPS_LAT($_) if (/GPS LATITUDE/);
  &Process_GPS_LON($_) if (/GPS LONGITUDE/);
  &Process_GPS_ALT($_) if (/GPS ALTITUDE/);
  &Process_GPS_HOR_VEL($_) if (/GPS HOR VEL/);
  &Process_GPS_VER_VEL($_) if (/GPS VER VEL/);
  &Process_GPS_TIME($_) if (/GPS TIME/);

  #
  # General Data
  #
  &Process_Tail($_) if (/0001-Tail/);
  &Process_ACID($_) if (/ACID: ACM MAC Address: acidValFromScript/);
  &Process_Ping($_) if (/Conducting.* Ping Test: /);
  &Process_Ping2($_) if (/Ping result: /);
# Commenting these out, we are not currently using the data.  2014/11/18
  #&Process_Flight_State($_) if (/Flight State ===/);
# Commenting these out, we are not currently using the data.  2014/11/18
  #&Process_GPS_AGL($_) if (/Above Ground Level/);
  &Process_ATG_Link($_) if (/- ATG LINK \w+$/);
  &Process_SBB_Link($_) if (/SBB_LINK_/);
# Commenting these out, we are not currently using the data.  2014/11/18
  #&Process_ABS_Coverage($_) if (/SIDE ABS COVERAGE/);
  &Process_ATG_APP_VERSION($_) if (/ATG Application Version/);
  &Process_AIRCARD_VERSION($_) if (/Aircard Version: /);
  &Process_SIGNAL_STRENGTH($_) if (/Signal Strength:/);
  &Process_AUTHENTICATION_STATUS($_) if (/Authentication Status for/);
  #
  &Process_Airlink_Log($_) if (/Airlink: - Aircard/);
  #
  # Error events Here
  #
  &Process_FAN_RPM($_) if (/Fan is spinning with rpm/);
  &Process_Power_Reset($_) if (/Last reset/);
  &Process_PCS_TEMP($_) if (/PCS Power Supply Temperature/);
  &Process_ACPU_REBOOT($_) if (/Last reset is due/);
  &Process_KeyLoadFail($_) if (/SW_KEYS: AbsControlServiceImpl: uploadKeysAMFDataToACM\(\): uploadKeysAMFFile : FALSE/);
  &Process_ACM_Status($_) if ( /downloadFileFromACM\(\): ConfigurationModuleConstants.ACM_CONNECTED_STATUS/ );
}

exit 0 if ( $#Output < 0 );

# Lets set up our Database connections
my $dbhs; my $dbhp;
#   http://www.connectionstrings.com/sql-server/
if ( ! $opt_D ) {
  $dbhs=&Create_SIT_DB_Connection if ( $opt_S );
  $dbhp=&Create_PROD_DB_Connection if ( $opt_P );
}

# Time to push the data
&Create_Output;

# Cleanup our lockfile
#unlink($LockFile);

exit 0;

##################
# Sub-Procs Here #
##################

# Output Format:
#
#  <TimeStamp> <$Tail> <Event Key> <Value>
#
sub Create_Output {
   my $sths; my $sthp;

  my $DBInsert="INSERT INTO ODS_LANDING.cl.LAND_CONSOLE_LOGS ( EVENT_DATE, TAIL_NBR, ALTITUDE, LATITUDE, LONGITUDE, HORIZONTAL_VELOCITY, VERTICAL_VELOCITY, EVENT_NAME, EVENT_VALUE_NUMBER, EVENT_VALUE_TEXT) VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
  # Best not to use this
  #my $DBInsert="INSERT INTO ODS_LANDING.cl.LAND_CONSOLE_LOGS WITH (TABLOCK ) ( EVENT_DATE, TAIL_NBR, ALTITUDE, LATITUDE, LONGITUDE, HORIZONTAL_VELOCITY, VERTICAL_VELOCITY, EVENT_NAME, EVENT_VALUE_NUMBER, EVENT_VALUE_TEXT) VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";

  if ( ! $opt_D ) {
    # We can save time/effort and prepare the Insert early then substitude on the loop
    $sths = $dbhs->prepare($DBInsert) if ( $opt_S );
    $sthp = $dbhp->prepare($DBInsert) if ( $opt_P );
  }

  print "  Inserting $#Output Lines.\n";
  foreach $Loop (@Output) {

    # Looks like we don't have complete gps data for an early entry
    next if ( $Loop =~ /_Unknown/ );

    my ( $Var1, $Var2, $Var3, $Var4, $Var5, $Var6, $Var7, $Var8, $Var9, $Var10 )=split(',', $Loop);
    undef($Var9) if ( ( $Var9 ) &&  ( $Var9 =~ /NULL/ ) );
    undef($Var10) if  ( ( $Var9 ) && ( $Var10 =~ /NULL/ ) );
 
    # Fixing a space issue I hope
    $Var1 =~ s/^ +//; $Var1 =~ s/ +$//;
    $Var2 =~ s/^ +//; $Var2 =~ s/ +$//;
    $Var3 =~ s/^ +//; $Var3 =~ s/ +$//;
    $Var4 =~ s/^ +//; $Var4 =~ s/ +$//;
    $Var5 =~ s/^ +//; $Var5 =~ s/ +$//;
    $Var6 =~ s/^ +//; $Var6 =~ s/ +$//;
    $Var7 =~ s/^ +//; $Var7 =~ s/ +$//;
    $Var8 =~ s/^ +//; $Var8 =~ s/ +$//;
    $Var9 =~ s/^ +// if ( $Var9 ); $Var9 =~ s/ +$// if ( $Var9 );
    $Var10 =~ s/^ +// if ( $Var10 ); $Var10 =~ s/ +$// if ( $Var10 );

    if ( ! $opt_D ) {
      $sths->execute($Var1,$Var2,$Var3,$Var4,$Var5,$Var6,$Var7,$Var8,$Var9,$Var10) || die "Couldn't execute statement: ".$sths->errstr." on $Loop\n" if ( $opt_S );
      $sthp->execute($Var1,$Var2,$Var3,$Var4,$Var5,$Var6,$Var7,$Var8,$Var9,$Var10) || die "Couldn't execute statement: ".$sthp->errstr." on $Loop\n" if ( $opt_P );
    } else {
      print "Executing execute($Var1,$Var2,$Var3,$Var4,$Var5,$Var6,$Var7,$Var8,$Var9,$Var10)\n";
    }
  }
}


sub signal_handler {
#    unlink($LockFile);
#    die "Caught a signal $!.  Removed LockFile: $LockFile.\n";
    die "Caught a signal $!.\n";
    exit 0;
}


sub Create_SIT_DB_Connection {

  # Function:     dbh_connect
  # Description:  Creates a connection to a database
  # Arguments:    none
  # Returns:      $db_conn - database connection handle
  #
  my ($dbhs);
  # DB Info
  my $dbuser="NETOPS_USR_RO";
  my $dbpasswd="Up5!w0N#";
  my $Database="ODS_Landing";
  my $Port="1433";

  # SIT
  my $Target="SIT";
  my $Host="10.1.100.190";


  #
  # Manual Test:
  #  https://sites.google.com/site/fagonas/li/small-things
  #  /usr/local/sqsh/bin/sqsh -SSIT -U NETOPS_USR_RO -PUp5!w0N#
  # 
  # Truncate the table:
  #  isql -v SIT NETOPS_USR_RO Up5!w0N#
  #  TRUNCATE TABLE ODS_LANDING.cl.LAND_CONSOLE_LOGS
  #
  my $dsn="dbi:ODBC:DRIVER={FreeTDS};Server=$Host;Port=1433;Database=$Database";
  $dbhs =DBI->connect( "$dsn;UID=$dbuser;PWD=$dbpasswd;{ PrintError => 1, AutoCommit => 0 }" ) || die "Couldn't connect to Database: " . DBI->errstr;
    
  if (! defined($dbhs) ) {
    print "Error connecting to DSN '$Database'\n";
    print "Error was:\n";
    print "$DBI::errstr\n";         # $DBI::errstr is the error received from the SQL server
    exit 0;
  }
    
  return $dbhs;
}    


sub Create_PROD_DB_Connection {

  # Function:     dbh_connect
  # Description:  Creates a connection to a database
  # Arguments:    none
  # Returns:      $db_conn - database connection handle
  #
  my ($dbhp);
  # DB Info
  my $dbuser="NETOPS_USR_RO";
  my $dbpasswd="Up5!w0N#";
  my $Database="ODS_Landing";
  my $Port="1433";

  # Prod
  my $Target="PROD";
  my $Host="10.241.4.64";

  #
  # Manual Test:
  #  https://sites.google.com/site/fagonas/li/small-things
  #  /usr/local/sqsh/bin/sqsh -SSIT -U NETOPS_USR_RO -PUp5!w0N#
  # 
  # Truncate the table:
  #  isql -v SIT NETOPS_USR_RO Up5!w0N#
  #  TRUNCATE TABLE ODS_LANDING.cl.LAND_CONSOLE_LOGS
  #
  my $dsn="dbi:ODBC:DRIVER={FreeTDS};Server=$Host;Port=1433;Database=$Database";
  $dbhp =DBI->connect( "$dsn;UID=$dbuser;PWD=$dbpasswd;{ PrintError => 1, AutoCommit => 0 }" ) || die "Couldn't connect to Database: " . DBI->errstr;
    
  if (! defined($dbhp) ) {
    print "Error connecting to DSN '$Database'\n";
    print "Error was:\n";
    print "$DBI::errstr\n";         # $DBI::errstr is the error received from the SQL server
    exit 0;
  }
    
  return $dbhp;
}    


sub Process_Tail {
  my $Line=$_[0];

  if ( $Line =~ /Extracting Tail/ ) {
    $Line =~ /.*Extracting Tail (\d+) Starting.*/;
    $Tail=$1;
  } else {
    $Line =~ /.*Extracting logs for tail (\d+).*/;
    $Tail=$1;
  }
}


sub Process_Ping {
  my $Line=$_[0];
  my $TimeStamp;
  my $Device;
  my $PLoss;
  my $PLatency;
  my $PRTT;

  if ( $Line =~ /100% packet loss/ ) {
    $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+)/;
    $TimeStamp=$1;
    $Device="AAA";
    $PLoss=100;
    $PLatency=99999;
    $PRTT=99999;
  } else {
    $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Conducting (.*) Ping Test.*(\d+)\% packet loss time (\d+)ms rtt.* = \d+\.\d+\/(\d+\.\d+)\/\d+\.\d+\/\d+\.\d+ ms/;

    $TimeStamp=$1;
    $Device=$2;
    $PLoss=$3;
    $PLatency=$4;
    $PRTT=$5;
  }

  #print " Got a Ping Result : \$TimeStamp :$TimeStamp: \$PLoss :$PLoss: \$PLatency :$PLatency: \$PRTT :$PRTT:\n";

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;

  # Clean up some ATG Fun...
  $Device =~ s/^ +//g;
  $Device =~ s/ Device$//g;
  $Device =~ s/ *$//g;
  print " Got a Ping Result : \$TimeStamp :$TimeStamp: \$PLoss :$PLoss: \$PLatency :$PLatency: \$PRTT :$PRTT:\n" if ( $Verbose
);

  # PLoss
  $Event=$Device."_Packet_Loss";
  $Insert="$TimeStamp, $Tail, $GPS_DATA, $Event, $PLoss, NULL";
  push(@Output, "$Insert");

# Commenting these out, we are not currently using the data.  2014/11/18
#  PLatency
  #$Event=$Device."_Packet_Latency";
  #$Insert="$TimeStamp, $Tail, $GPS_DATA, $Event, $PLatency, NULL";
  #push(@Output, "$Insert");

  # PRTT
  $Event=$Device."_Packet_RTT";
  $Insert="$TimeStamp, $Tail, $GPS_DATA, $Event, $PRTT, NULL";
  push(@Output, "$Insert");
}


sub Process_Ping2 {
  my $Line=$_[0];
  my $PLoss;
  my $PLatency;
  my $PRTT;

  if ( $Line =~ /100% packet loss/ ) {
    $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+)/;
    $TimeStamp=$1;
    $PLoss=100;
    $PLatency=99999;
    $PRTT=99999;
  } else {
    $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Ping result:.*(\d+)\% packet loss time (\d+)ms rtt.* = \d+\.\d+\/(\d+\.\d+)\/\d+\.\d+\/\d+\.\d+ ms/;

    $TimeStamp=$1;
    $PLoss=$2;
    $PLatency=$3;
    $PRTT=$4;
  }

  #print " Got a Ping Result : \$TimeStamp :$TimeStamp: \$PLoss :$PLoss: \$PLatency :$PLatency: \$PRTT :$PRTT:\n";

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  # PLoss
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_Packet_Loss, $PLoss, NULL";
  push(@Output, "$Insert");

# Commenting these out, we are not currently using the data.  2014/11/18
  # PLatency
  #$Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_Packet_Latency, $PLatency, NULL";
  #push(@Output, "$Insert");

  # PRTT
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_Packet_RTT, $PRTT, NULL";

  push(@Output, "$Insert");

}


sub Process_Flight_State {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Flight State ===> (.*)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, Flight_State, NULL, $State";

  push(@Output, "$Insert");

}


sub Process_ATG_Link {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*(ATG LINK \w+$)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_LINK, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_SBB_Link {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*(SBB_LINK_.*)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, SBB_LINK, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_ABS_Coverage {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* (\w+SIDE) ABS COVERAGE$/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ABS_COVERAGE, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_PCS_TEMP {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* PCS Power Supply Temperature (.*)$/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, PCS_TEMP, $State, NULL";

  push(@Output, "$Insert");
}


sub Process_FAN_RPM {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* Fan is spinning with rpm (.*)$/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, FAN_RPM, $State, NULL";

  push(@Output, "$Insert");
}


sub Process_GPS_LAT {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* GPS LATITUDE +(.*)$/;

  $TimeStamp=$1;
  $GPS_LAT=$2;

  if ($GPS_LAT =~ /[Ee]/) {
    $GPS_LAT = sprintf "%.12f", $GPS_LAT;
  }

#  push(@Output, "$TimeStamp, $Tail, GPS_LAT, $GPS_LAT");
  if ( ! $GPS_LAT_go ) {
    foreach $Loop (0..$#Output) {
      $Output[$Loop] =~ s/LAT_Unknown/$GPS_LAT/;
    }
    $GPS_LAT_go=1;
  }
}


sub Process_GPS_LON {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* GPS LONGITUDE +(.*)$/;

  $TimeStamp=$1;
  $GPS_LON=$2;

  if ($GPS_LON =~ /[Ee]/) {
    $GPS_LON = sprintf "%.12f", $GPS_LON;
  }

#  push(@Output, "$TimeStamp, $Tail, GPS_LON, $GPS_LON");
  if ( ! $GPS_LON_go ) {
    foreach $Loop (0..$#Output) {
      $Output[$Loop] =~ s/LON_Unknown/$GPS_LON/;
    }
    $GPS_LON_go=1;
  }
}


sub Process_GPS_ALT {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* GPS ALTITUDE +(.*)$/;

  $TimeStamp=$1;
  $GPS_ALT=$2;

  if ($GPS_ALT =~ /[Ee]/) {
    $GPS_ALT = sprintf "%.12f", $GPS_ALT;
  }

#  push(@Output, "$TimeStamp, $Tail, GPS_ALT, $GPS_ALT");
  if ( ! $GPS_ALT_go ) {
    foreach $Loop (0..$#Output) {
      $Output[$Loop] =~ s/ALT_Unknown/$GPS_ALT/;
    }
    $GPS_ALT_go=1;
  }
}


sub Process_GPS_HOR_VEL {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* GPS HOR VEL +(.*)$/;

  $TimeStamp=$1;
  $GPS_HOR_VEL=$2;

  if ($GPS_HOR_VEL =~ /[Ee]/) {
    $GPS_HOR_VEL = sprintf "%.12f", $GPS_HOR_VEL;
  }

#  push(@Output, "$TimeStamp, $Tail, GPS_HOR_VEL, $GPS_HOR_VEL");
  if ( ! $GPS_HOR_VEL_go ) {
    foreach $Loop (0..$#Output) {
      $Output[$Loop] =~ s/HVEL_Unknown/$GPS_HOR_VEL/;
    }
    $GPS_HOR_VEL_go=1;
  }
}


sub Process_GPS_VER_VEL {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* GPS VER VEL +(.*)$/;

  $TimeStamp=$1;
  $GPS_VER_VEL=$2;

  if ($GPS_VER_VEL =~ /[Ee]/) {
    $GPS_VER_VEL = sprintf "%.12f", $GPS_VER_VEL;
  }

#  push(@Output, "$TimeStamp, $Tail, GPS_VER_VEL, $GPS_VER_VEL");
  if ( ! $GPS_VER_VEL_go ) {
    foreach $Loop (0..$#Output) {
      $Output[$Loop] =~ s/VVEL_Unknown/$GPS_VER_VEL/;
    }
    $GPS_VER_VEL_go=1;
  }
}


sub Process_GPS_TIME {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* GPS TIME +(.*)$/;

  $TimeStamp=$1;
  $GPS_TIME=$2;

#  push(@Output, "$TimeStamp, $Tail, GPS_TIME, $GPS_TIME");
  if ( ! $GPS_TIME_go ) {
    foreach $Loop (0..$#Output) {
      $Output[$Loop] =~ s/TIME_Unknown/$GPS_TIME/;
    }
    $GPS_TIME_go=1;
  }
}


sub Process_GPS_AGL {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;
  my $State2;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* Above Ground Level +====>(.*) +feet$/;

  $TimeStamp=$1;
  $State=$2;

  if ($State =~ /[Ee]/) {
    $State = sprintf "%.12f", $State;
  }

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, GPS_ABOVE_GROUND_LEVEL, $State, NULL";

  push(@Output, "$Insert");
}


sub Process_ACPU_REBOOT {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* Last reset is due to (.*)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ACPU_REBOOT, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_ATG_APP_VERSION {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*ATG Application Version.*: +(.*)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_APP_VERSION, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_AIRCARD_VERSION {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Aircard Version: +(.*)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, AIRCARD_VERSION, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_SIGNAL_STRENGTH {
  my $Line=$_[0];
  my $TimeStamp;
  my $State; my $State2;

  # Drop a garbage AMP line.
  return if ( $Line =~ /AMP:/ );

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Signal Strength: +(.*)/;

  $TimeStamp=$1;
  $State=$2;

  if ($State =~ /[Ee]/) {
    $State = sprintf "%.12f", $State;
  }

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_SINR, $State, NULL";

  push(@Output, "$Insert");
}


sub Process_AUTHENTICATION_STATUS {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Authentication Status for +(.*)/;

  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, AUTHENTICATION_STATUS, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_KeyLoadFail {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*SW_KEYS: AbsControlServiceImpl: uploadKeysAMFDataToACM\(\): uploadKeysAMFFile : (.*)/;


  $TimeStamp=$1;
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, SWKEY_LOAD_SUCCESS, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_ACID {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*ACID: ACM MAC Address: acidValFromScript +: +(.*)/;

  $TimeStamp="$1";
  $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ACID, NULL, $State";

  push(@Output, "$Insert");
}

sub Process_Power_Reset {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+)...(.*)/;

  my $TimeStamp="$1";
  my $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ATG_POWER_RESET, NULL, $State";

  push(@Output, "$Insert");
}


sub Process_Airlink_Log {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) Airlink: - Aircard .*, Cell (.*), Sector (.*)/;

  # There are instances where these fields are NOT populated ( crap entry from Aircard. Just skip )
  return if ( ! $1 );
  return if ( ! $2 );
  return if ( ! $3 );

  my $TimeStamp="$1";
  my $Cell="$2";
  my $Sector="$3";

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;

  # CELL
  $Insert="$TimeStamp, $Tail, $GPS_DATA, AIRCARD_CELL, NULL, $Cell";
  push(@Output, "$Insert");
  # Sector
  $Insert="$TimeStamp, $Tail, $GPS_DATA, AIRCARD_SECTOR, NULL, $Sector";
  push(@Output, "$Insert");
}


sub Process_ACM_Status {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*downloadFileFromACM\(\): ConfigurationModuleConstants.ACM_CONNECTED_STATUS : (.*)/;

  my $TimeStamp="$1";
  my $State=$2;

  # Database doesn't like the comma
  $TimeStamp =~ s/,/./;
  $Insert="$TimeStamp, $Tail, $GPS_DATA, ACM_ERROR, NULL, ACM did not connect";

  push(@Output, "$Insert");
}

