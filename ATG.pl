#!/usr/bin/perl -w
$| = 1;

# Additions/Changes
# 1) Fix time ( 601 seconds -> 10 minutes, 1 second )
# 2) Redo ASA/BSA logic.  If it goes ASA-> !BSA, something bad happened!

use strict;
use diagnostics;
use Date::Calc qw(:all);
use Date::Manip;
use Class::Date;

# GetOpt
use vars qw( $opt_h $opt_v $opt_u $opt_f $opt_t $opt_all $opt_e $opt_temp $opt_flightstates $opt_time $opt_auth $opt_stats $opt_start $opt_end $opt_pings );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v u f=s e t all temp flightstates time auth stats start=s end=s pings ");


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
  print "  -t = Use TechSupport console.log ( /tmp/console-<user>.log )\n";
  print "  -u = Use local user console.log ( ./console-<user>.log )\n";
  print "  -e = Show Display known \"error related lines\"\n";
  print " --temp = Show Verbose Temperature Readings\"\n";
  print " --flightstates = Show changes in flight states\n";
  print " --auth = Show Authentication Status information\n";
  print " --pings = Show Ping Status information\n";
  print " --time = Show time differences\n";
  print " --stats = Show ATG Stats/Versions\n";
  print " --all = Show all options\n";
  print " --start <Date> = Specify a starting date for processing.\n";
  print " --end <Date> = Specify an ending date for processing.\n";
  print " ** Date is in the format of 2014-02-03 19:00:10\n";
  print " ** The time portion of the Date is optional.\n";
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
my $FlightMaxTemp=0;  my $FlightMaxTempString=""; my $FlightTempErrors=0;
#
my $Line;
my $Loop;my %Auths; my %AuthAddr; my %FlightAuths; my %FlightAuthAddr;
my @Altitudes; 
my $Flight_State="";
my $First_GPS_TIME;
my $Last_GPS_TIME;
my $OpenCommand;
my $ATGVersion=0; my $AircardVersion="Undefined";
my $AircardReset="False";
my $CheckAircardReset="0";
my $AircardState="";
my $OrigATGVersion;
my $OrigAircardVersion;
my $OrigACID="";
my $ACID="";
my $PlacingCall="F";
my $Coverage="";
my $Resets=0;
my $Ratio=0;
my $LatencyRatio=0;
my $FlightCount=0;
my $ASA="F";
my $ASATime="";
my $LastSINR="";
my $LastSINRCount=0;
my $CountMin=20;
my $SINRGood=0; 
my $SINRBad=0;
my $CoW="false";
my $CoWINIT="false";
# Ping Stats
my @Pings;
my $PingCount=0;
my $AVGPacketLoss=0;
my $MinLatency=99999999;
my $AVGLatency=0;
my $sMaxLatency=0;
my $MaxLatency=0;
my $TotalMinLatency=999999999;
my $TotalAVGLatency=0;
my $TotalMaxLatency=0;
my $TotalPingCount=0;
# Errors
my %Errors;
my %Investigation;
my %FlightErrors;
my %QoS; $QoS{6}="-1"; $QoS{7}="-1";
# Lets track some time
my $TotalDays=0; my $TotalHours=0; my $TotalMins=0; my $TotalSecs=0;


#
# Lets get our start and Finish
#
my $Start; my $End; my $Date1;
my $ParseStart="F";
# Nail down our Beginning Date
if ( $opt_start ) {
  $Start=$opt_start;
  $ParseStart="T";
} else {
  $Start="1969-12-31";
  $ParseStart="F";
}

# Nail down our End Date
my $ParseEnd="F";
if ( $opt_end ) {
  $End=$opt_end;
my $ParseEnd="T";
} else {
  $End="2052-12-31";
  $ParseEnd="F";
}
my $Date2=ParseDate("$Start");
my $Date3=ParseDate("$End");


my %Mons = ("01"=>'Jan',"02"=>'Feb',"03"=>'Mar',"04"=>'Apr',"05"=>'May',"06"=>'Jun',"07"=>'Jul',"08"=>'Aug',"09"=>'Sep',"10"=>'Oct',"11"=>'Nov',"12"=>'Dec');
my %RMons = ("Jan"=>'01',"Feb"=>'02',"Mar"=>'03',"Apr"=>'04',"May"=>'05',"Jun"=>'06',"Jul"=>'07',"Aug"=>'08',"Sep"=>'09',"Oct"=>'10',"Nov"=>'11',"Dec"=>'12');

my @Days = qw(Sun Mon Tue Wed Thu Fri Sat Sun);

if ( $opt_t ) {
  $opt_f="/tmp/console-".$User.".log";
} 

if ( $opt_u ) {
  $opt_f="console-".$User.".log";
} 

if ( ! $opt_f ) {
  $opt_f="console.log";
}

#
# What kind of file are we opening?
# 
if ( ( $opt_f =~ /\.tar.gz$/ ) || ( $opt_f =~ /\.tgz$/ )) {
  print "Opening Tar-GZ\n" if ( $opt_v ); 
  $OpenCommand="tar xzvOf $opt_f |";
} elsif ( $opt_f =~ /\.gz/ ) {
  print "Opening Compressed\n" if ( $opt_v ); 
  $OpenCommand="/bin/gunzip -c $opt_f |";
} else {
  print "Opening Un-compressed\n" if ( $opt_v ); 
  $OpenCommand="<$opt_f";
}

open(INPUT, "$OpenCommand") || die "Can't open $opt_f :$?:\n";
while(<INPUT>) {
  chomp;
  $Line=$_;


  # Clean trash
  next if ( $Line =~  /^$/ );
  # Temp until we know if we need the non-date stamped lines
  next unless (  $Line =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d/ );
  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),\d\d\d/;
  
  my $TestDate=$1;

  # Lets check our Date Range
  if ( ( $ParseStart eq "T" ) || ( $ParseEnd eq "T" ) ) {
    $Date1=ParseDate("$TestDate");
  }
  #
  if ( (  $opt_start ) && ( $ParseStart eq "T" ) ) {
    my $Begin=Date_Cmp($Date1, $Date2);
    next if ( $Begin < 0 );
    $ParseStart="F";
    print "\$ParseStart :$ParseStart:\n";
  }
  if ( (  $opt_end ) && ( $ParseEnd eq "T" ) ) {
    my $Finish=Date_Cmp($Date3, $Date2);
    next if ( $Finish < 0 );
    $ParseEnd="F";
    print "\$ParseEnd :$ParseEnd:\n";
  }

  &Process_ATGVersion("$Line") if ( $Line =~ /ATG Application Version/ );
  &Process_AircardVersion("$Line") if ( $Line =~ /Aircard Version:/ );

  &Process_CellOnWheels("$Line") if ( $Line =~ /CellOnWheels=/);
  &Process_Authentication_Mesg("$Line") if ( $Line =~ /Authentication Message response/);
  &Process_Coverage("$Line") if ( $Line =~ /ABS COVERAGE/);
  &Process_Flight_State_Change("$Line") if ( $Line =~ /Change in FLIGHT State/);
  &Process_Flight_State_Change("$Line") if ( $Line =~ /Coverage.*FLIGHT/);
  &Process_ATG_LINK("$Line") if ( $Line =~ /ATG LINK [up|down]/);
  &Process_ACID("$Line") if ( $Line =~ /ACID: ACM MAC Address: acidValFromScript/);
  &Process_ACID2("$Line") if ( $Line =~ /downloadFileFromACM\(\): ConfigurationModuleConstants.ACM_CONNECTED_STATUS/);
  &Process_Ping_Test("$Line") if ( $Line =~ /Reset Count: 1 Ping failure: 5/);
  &Process_Ping_Test2("$Line") if ( $Line =~ /ICMP ping to AAA server is failed/);
  &Process_Ping_Latency_16_1("$Line") if ( $Line =~ /Ping result:/);
  &Process_Ping_Latency_2_1("$Line") if ( $Line =~ /Conducting AAA Ping Test:./);
  &Process_Ping_Threshold("$Line") if ( $Line =~ /PING_FAILURE_THRESHOLD...5/);
  &Process_Signal_Strength("$Line") if ( $Line =~ /Signal Strength:/);
  &Process_Power_Reset("$Line") if ( $Line =~ /Last reset/);
  &Process_Link_Down("$Line") if ( $Line =~ /atgLink[Down|Up]/);
  &Process_QoS("$Line") if ( $Line =~ /Flow for QoS Profile:/);
  &Process_Flight_State("$Line") if ( $Line =~ /Flight State \=\=\=/);
  &Process_GPS_Time("$Line") if ( $Line =~ /\-.*GPS TIME/);
  &Process_Authentication_Status("$Line") if ( $Line =~ /Authentication Status/);
  &Process_Temp("$Line")  if ( $Line =~ /PCS Power Supply Temp/ );
}

&Show_Flight_States if ( $opt_flightstates );
&Show_GPS_Time if ( $opt_time );
&Show_Authentication_Status if ( $opt_auth );
&Display_Errors if ( $opt_e );
&Display_Pings if ( $opt_pings );
&Display_Stats if ( $opt_stats );

# Nothing to see below here, move along citizen. 
exit 0;




#################
# Sub Procs Here #
##################
sub Display_Stats {
  my $AircardType;
  my $tmp;

  print "\n";
  print "Stats Found:\n";
  print "  ATG ACID : $ACID\n";
  print "      *** Originally was $OrigACID!!! ***\n" if ( $OrigACID );
  print "  ATG Version : $ATGVersion\n";
  print "      *** Originally was $OrigATGVersion!!! ***\n" if ( $OrigATGVersion );
  print "  Aircard Version : $AircardVersion\n";
  if ( $AircardVersion =~ /Bigsky/ ) {
    $AircardType="Type: Rev-A"
  } elsif ( $AircardVersion =~ /Aircard2/ ) {
    $AircardType="Type: Rev-B"
  } else {
    $AircardType="Type: Unknown"
  }
  print "    $AircardType\n" if ( $AircardType );
  print "      *** Originally was $OrigAircardVersion!!! ***\n" if ( $OrigAircardVersion );





  if ( $FlightCount != 0 ) {
    $TotalAVGLatency=$TotalAVGLatency/$FlightCount;
    #  $TotalAVGLatency = sprintf "4%.4f", $TotalAVGLatency;

    # Lets normalize our time
    if ( $TotalSecs > 59 ) {
      ($tmp, $TotalSecs) = (int $TotalSecs / 60, $TotalSecs % 60);
       $TotalMins += $tmp;
    }
  
    if ( $TotalMins > 59 ) {
      ($tmp, $TotalMins) = (int $TotalMins / 60, $TotalMins % 60);
       $TotalHours += $tmp;
    }
  
    if ( $TotalHours > 24 ) {
      ($tmp, $TotalHours) = (int $TotalHours / 60, $TotalHours % 24);
       $TotalDays += $tmp;
    }
  

    print "  Flights processed: $FlightCount\n";
    print "    Time Above Service Altitude :\n";
    print "       Days: $TotalDays    Hours: $TotalHours    Mins: $TotalMins    Secs: $TotalSecs\n";

    if ( scalar ( keys ( %Auths ) ) > 0 ) {
      print "  Total Unique IP Addresses Authenticated : ".scalar( keys (%AuthAddr) )."\n";
      print "  Total Authentication Requests : ".scalar( keys (%Auths) )."\n";
    } else {
      print "No authentication requests.\n";
    }
  } else {
    print "No flights found.\n";
  }
  print "\n";
}


sub Process_Signal_Strength {
  my $StateLine=$_[0];
  
  return if ( $ASA eq "T" ); 
  return if ( $Coverage eq "INSIDE ABS COVERAGE" );
  return if ( $StateLine =~ /[GOOD|BAD]/ );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.*Signal Strength: +(.*)$/;

  my $Date=$1;
  my $SINR=$2;

  if ( ( $SINR eq "-27.0" ) && ( $LastSINR eq "-27.0" ) ) {
    $LastSINRCount++;
  }
  if ( $LastSINR ne $SINR ) {
    if (( $LastSINR eq "-27.0" ) && ( $LastSINRCount > $CountMin ) ) {
      push(@Altitudes,"Just ended a streak of -27 $LastSINRCount times at $1");
      $Investigation{"Neg27-$Date"}="Neg-27: Experienced  ended a streak of -27 $LastSINRCount times at $Date";
    }
    $LastSINRCount=0;
  }
  $LastSINR=$SINR;

  push(@Altitudes, "    Signal Strength: $1 -- $2") if ( $SINR < 6 );
  $SINRGood++ if ( $SINR >= 6 ); 
  $SINRBad++ if ( $SINR < 6 ); 



}
sub Display_Errors {
  print "\n";
  if ( $ATGVersion ne $BlessedATG ) {
    $Errors{"ATG Version"}="This ATG is on version $ATGVersion instead of $BlessedATG!";
  }
  print "Errors Found:\n"; 
  if ( ! keys ( %Errors ) ) {
    print " * No errors logged.\n";
  } else {
    foreach $Loop ( sort ( keys( %Errors ) ) ) {
      print "  $Errors{$Loop}\n";
    }
  }
  print "\n";
  print "Indicators to Investigate:\n"; 
  if ( ! keys ( %Investigation ) ) {
    print " * Nothing identified.\n";
  } else {
    foreach $Loop ( sort ( keys( %Investigation ) ) ) {
      print "  $Investigation{$Loop}\n";
    }
  }
  print "\n";
}


sub Display_Pings {
  print "\n";
  print "Pings Recorded :\n"; 
  foreach $Loop (0..$#Pings) {
   print "  $Pings[$Loop]\n";
  }
  print "\n";
}


sub Process_aircardState {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.* aircardState : +(.*)$/;

  if ( $AircardState ne $2 ) { 
    push(@Altitudes, "  AircardState Change : $1 -- $2");
    $AircardState=$2;
  }
  if ( $AircardState eq "READY_FOR_OPERATION" ) {
    if ( $PlacingCall eq "T" ) {
      push(@Altitudes, "  AircardState Change : $1 -- $2");
      push(@Altitudes, "  ** Tried to place a ground call, Aircard did not respond!!!\n");
    } else {
      $PlacingCall="T";
    }
  } elsif ( $AircardState eq "CALL_ESTABLISHED" ) {
    $PlacingCall="F";
  }
}


sub Process_Flight_State_Change {
  my $StateLine=$_[0];
  if ( $StateLine =~ /Change/ ){
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.* (AMP:.*)$/;
    push(@Altitudes, "FlightState Change : $1 -- $2");
  } elsif ( $StateLine =~ /Coverage/) {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.* (Coverage .*)$/;
    push(@Altitudes, "FlightState Change : $1 -- $2");
  }
}


sub Process_Flight_State {
  my $StateLine=$_[0];


  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.*\> (.*)$/;
  my $Date=$1;
  my $NewState=$2;

  if (( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" ) && ( $NewState eq "ABOVE_SERVICE_ALTITUDE" )){
    $ASA="T";
    $ASATime="$Date";
  }
  if (( $Flight_State eq "ABOVE_SERVICE_ALTITUDE" ) && ( $NewState ne "ABOVE_SERVICE_ALTITUDE" )){
    #  We just left ASA, Lets handle the Ping Checks!
    $FlightCount++;
    if ( $PingCount == 0 ) {
      $AVGLatency=0;
    } else {
      $AVGLatency=$AVGLatency/$PingCount;
      $AVGLatency = sprintf "%.2f", $AVGLatency;
    }
    push(@Altitudes, " ");
    push(@Altitudes, "  Flight Stats: ");
    push(@Altitudes, "    Time ASA: $ASATime");
    push(@Altitudes, "    Time BSA: $Date");
    #my $PDate1=ParseDate("$ASATime");
    #my $PDate2=ParseDate("$Date");
    my ( $Year1, $Mon1, $Day1, $Hour1, $Min1, $Sec1 ) = &Conv_Time($ASATime);
    my ( $Year2, $Mon2, $Day2, $Hour2, $Min2, $Sec2 ) = &Conv_Time($Date);
    my ($days, $hours, $mins, $secs)=Delta_DHMS( $Year1, $Mon1, $Day1, $Hour1, $Min1, $Sec1, $Year2, $Mon2, $Day2, $Hour2, $Min2, $Sec2);
    $TotalDays += $days;
    $TotalHours += $hours;
    $TotalMins += $mins;
    $TotalSecs += $secs;
    if ( scalar ( keys ( %FlightAuths ) ) > 0 ) {
      push(@Altitudes, "      Total IP Addresses Authenticated : ".scalar( keys (%FlightAuths) ) );
    } else {
      push(@Altitudes, "      NO Addresses Authenticated this flight!!!");
    }
    if ( scalar ( keys ( %FlightAuths ) ) > 0 ) {
      push(@Altitudes, "      Unique IP Addresses Authenticated : ".scalar( keys (%FlightAuthAddr) ) );
    }
    push(@Altitudes, "    Flight Length : $days days, $hours hours, $mins minutes, $secs seconds");
    push(@Altitudes, "    Max Latency this time ASA: $MaxLatency");
    push(@Altitudes, "    AVG Latency this time ASA: $AVGLatency");
    push(@Altitudes, "    Min Latency this time ASA: $MinLatency");
    $TotalMinLatency = $MinLatency if ( $TotalMinLatency > $MinLatency );
    $TotalAVGLatency += $AVGLatency;
    $TotalMaxLatency = $MaxLatency if ( $TotalMaxLatency < $MaxLatency );
    $TotalPingCount += $PingCount;
    $MinLatency=9999999;
    $AVGLatency=0;
    $MaxLatency=0;
    $PingCount=0;
    if ( $FlightTempErrors > 0 ) {
      push(@Altitudes, "    * Flight Maximum temp exceeded $MaxSafeTemp $FlightTempErrors times with a maximum of $FlightMaxTemp");
      $FlightTempErrors=0;
      $FlightMaxTemp=0;
    }
    if ( $SINRBad+$SINRGood == 0 ) {
      $Ratio=0;
    } else {
      $Ratio=($SINRGood/($SINRBad+$SINRGood))*100;
      $Ratio = sprintf "%.2f", $Ratio;
      push(@Altitudes, "    Signal Strenth Summary: $SINRGood Good entries while above altitude");
      push(@Altitudes, "    Signal Strenth Summary: $SINRBad   Bad entries while above altitude");
      push(@Altitudes, "    Very Bad SINR Ratio detected at $Date") if ( $Ratio < 75 );
      push(@Altitudes, "    Signal Strenth Ratio: $Ratio percent of the reported signal strength was >6 while ASA.");
      push(@Altitudes, " ");
      $SINRGood=0;
      $SINRBad=0;
    }
    $Investigation{"Ratio-$Date"}="Very Bad SINR Ratio detected at $Date" if ( $Ratio < 75 );
    push(@Altitudes, " ");
  }
  if ( $Flight_State !~ $NewState ) {
    $Flight_State=$2;
    print "Pushing $1 -- $2\n" if ( $Verbose );
    push(@Altitudes, "FlightState Change : $1 -- $2");
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


sub Process_Power_Reset {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) .* (Last reset is due.*)/;
  if ( $Coverage !~ $2 ) {
    $Coverage=$2;
    print "Pushing $1 -- $2\n" if ( $Verbose );
    push(@Altitudes, "Power Reset        : $1 -- $2");
    $Flight_State="NULL";
  }
}


sub Process_CellOnWheels {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d).*CellOnWheels=(\w+).*/;
  
  my $Date=$1;

  $CoW=$2;

  if (( $StateLine =~ /System Configurations being initialised/ ) && ( $CoW eq "true" )) {
    $CoWINIT="true";
    print "Pushing $Date -- CoW Status : $CoW\n" if ( $Verbose );
    push(@Altitudes, "  *** ATG Initialized with CellOnWheels Status! : $Date -- $CoW");
    if ( $CoW eq "true" ) {
      $Investigation{"CoW-$Date"}="*** ATG Initialized with ATG was in CoW at $Date";
    }
  }
  print "Pushing $Date -- CoW Status : $CoW\n" if ( $Verbose );
  push(@Altitudes, "  CellOnWheels Status! : $Date -- $CoW");
  if ( $CoW eq "true" ) {
    $Investigation{"CoW-$Date"}="ATG was in CoW at $Date";
  }
}


sub Process_QoS {
#  return;
  my $StateLine=$_[0];
  my $Date; my $Chan; my $Stat; my $StatVal;

  if ( $StateLine =~ /RevA/ ) { 
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d).*Flow for QoS Profile: +(\d) +is: (.*)/;
    $Date=$1; 
    $Chan=$2; 
    $Stat=$3; 
    $StatVal="";
  } elsif ( $StateLine =~ /RevB/ ) { 
    # We don't have a breakdown on this line yet.
    return;
  } else {
    # What version is this???
    return;
  }
    

  if ( $QoS{$Chan} ne $Stat ) {
    if ( $Chan < 0 ) {
      $StatVal="Aircard QoS is DOWN";
    } else {
      $StatVal="Aircard QoS is UP";
    }
    push(@Altitudes, "  QoS Changed : $Date -- $Chan : $StatVal");
    $QoS{$Chan}=$Stat;
    
  }
}


sub Process_Link_Down {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d).*(NCS: +UnifyConnection:.*)/;
  if ( $Coverage !~ $2 ) {
    $Coverage=$2;
    print "Pushing $1 -- $2\n" if ( $Verbose );
    push(@Altitudes, "Link Change        : $1 -- $2");
  }
}


sub Process_Authentication_Mesg {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d).*Authentication Message response +(.*)/;
  if ( $2 == 5 ) {
    print "Check Provisioning : $1 -- Authentication Message response $2" if ( $Verbose );
    $Investigation{"Authentication-5"}="Check Provisioning : $1 -- Authentication Message response  5";
  }
}


sub Show_Flight_States {
  print "\n";
  print "Flight State Changes:\n";
  foreach $Loop (0..$#Altitudes) {
   #print "\$Altitudes[$Loop] :$Altitudes[$Loop]:\n";
   print "  $Altitudes[$Loop]\n";
  }
  print "\n";
}

sub Process_GPS_Time {
  my $GPSLine=$_[0];
  $First_GPS_TIME=$GPSLine if ( ! $First_GPS_TIME );
  $Last_GPS_TIME=$GPSLine;
}


sub Show_GPS_Time {
  my $ATG1; my $ATG2; my $GPS1; my $GPS2;
  my $days; my $hours; my $mins; my $secs;
  my $Year1; my $Mon1; my $Day1; my $Hour1; my $Min1; my $Sec1;
  my $Year2; my $Mon2; my $Day2; my $Hour2; my $Min2; my $Sec2;
  $First_GPS_TIME =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d)\,\d\d\d.*GPS TIME +(.*)/;
  #
  $ATG1=$1;
  $2 =~ /(\w\w\w) +(\w\w\w) +(\d\d) +(\d\d:\d\d:\d\d) +UTC +(\d\d\d\d)/;
  $GPS1=$5."-".$RMons{$2}."-".$3." $4";
  #
  $ATG1 =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
  ( $Year1, $Mon1, $Day1, $Hour1, $Min1, $Sec1 ) = &Conv_Time($ATG1);
  $GPS1 =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
  ( $Year2, $Mon2, $Day2, $Hour2, $Min2, $Sec2 ) = &Conv_Time($GPS1);
  #
  #
  # 
  # Get the difference
  # 
  ($days, $hours, $mins, $secs) =
  Delta_DHMS( $Year1, $Mon1, $Day1, $Hour1, $Min1, $Sec1,  # earlier
              $Year2, $Mon2, $Day2, $Hour2, $Min2, $Sec2); # later
  print "\n";
  print "First Sync\n";
  print "  ATG Time :$ATG1:\n";
  print "  GPS Time :$GPS1:\n";
  print "Difference: $days days, $hours hours, $mins minutes, $secs seconds\n";

  $Last_GPS_TIME =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d)\,\d\d\d.*GPS TIME +(.*)/;
  #
  $ATG2=$1;
  $2 =~ /(\w\w\w) +(\w\w\w) +(\d\d) +(\d\d:\d\d:\d\d) +UTC +(\d\d\d\d)/;
  $GPS2=$5."-".$RMons{$2}."-".$3." $4";
  #
  $ATG2 =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
  ( $Year1, $Mon1, $Day1, $Hour1, $Min1, $Sec1 ) = &Conv_Time($ATG1);
  $GPS2 =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
  ( $Year2, $Mon2, $Day2, $Hour2, $Min2, $Sec2 ) = &Conv_Time($GPS1);
  #
  #
  # 
  # Get the difference
  # 
  ($days, $hours, $mins, $secs) =
  Delta_DHMS( $Year1, $Mon1, $Day1, $Hour1, $Min1, $Sec1,  # earlier
              $Year2, $Mon2, $Day2, $Hour2, $Min2, $Sec2); # later
  print "Last Sync\n";
  print "  ATG Time :$ATG2:\n";
  print "  GPS Time :$GPS2:\n";
  print "Difference: $days days, $hours hours, $mins minutes, $secs seconds\n";
  print "\n";
}


sub Conv_Time {
  my $Time=$_[0];

  $Time =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;
  my $Year=$1;
  my $Mon=$2;
  my $Day=$3;
  my $Hour=$4;
  my $Min=$5;
  my $Sec=$6;
  return( $Year, $Mon, $Day, $Hour, $Min, $Sec );
}


sub Process_Authentication_Status {
  my $Line=$_[0];
  print "\$Line :$Line:\n" if ( $Verbose );
#2014-01-19 15:08:45,601 - Authentication Status for 192.168.1.105/10175@airborne.aircell.com in domainnull :Success
  $Line =~ /(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d),\d\d\d.*Authentication Status for +(\d+\.\d+\.\d+\.\d+)\/.* :(\w+)$/;
  my $Date=$1;
  my $Time=$2;
  my $Addr=$3;
  my $Status=$4;
  my $AuthLine="$Date - $Time - $Addr - $Status";
  $Auths{"$AuthLine"}="1";
  $AuthAddr{$Addr}="1";
  $FlightAuths{"$AuthLine"}="1";
  $FlightAuthAddr{$Addr}="1";
}


sub Show_Authentication_Status {
  print "\n";
  print "Authentication Stats:\n";
  foreach $Loop ( sort ( keys( %Auths ) ) ) {
    print " $Loop\n";
  }
  print "\n";
}


sub Process_Temp {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d),\d\d\d.*PCS Power Supply Temperature +(.*)$/;
  my $Date="$1 $2";
  my $Temp=$3;
  if ( $MaxTemp < $Temp ) {
    $MaxTemp=$Temp;
    $MaxTempString="$MaxTemp recorded at $Date";
    $FlightMaxTemp=$Temp;
    $FlightMaxTempString="$MaxTemp recorded at $Date";
  }
  print "$Date - $Temp\n" if ( $opt_temp );
  if ( $Temp >= $MaxSafeTemp ) {
    $TempErrors++;
    $Errors{"Temperature"}="Temperature Error : $MaxTempString.  Temp above $MaxSafeTemp degrees $TempErrors times.";
    $Errors{"Temperature.1"}="  * Investigate Airflow, Fans, Installation conditions and other factors.  NOT an immediate RMA !!!";
    $FlightErrors{"Temperature"}="Temperature Error : $MaxTempString.  Temp above $MaxSafeTemp degrees $TempErrors times.";
    $FlightTempErrors++;
  }
}


sub Process_ATGVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d,\d\d\d) .*ATG Application Version +: +(.*)$/;

  my $Date="$1";
  my $TempVersion=$2;

  push(@Altitudes, "    ATG Version : $1 -- $2");

  $ATGVersion=$TempVersion if ( $ATGVersion eq "0" );
  if ( $ATGVersion ne $TempVersion ) {
    $OrigATGVersion=$ATGVersion;
    $ATGVersion=$TempVersion;
#    print "ERROR!  ATG Version changed mid log!\n";
#    print "    Old=$OrigATGVersion : New=$ATGVersion\n";
    push(@Altitudes, " $Date *** Error: ATG Version changed mid log from $OrigATGVersion to $ATGVersion at $1");
    $Investigation{"ATGVersion $Date"}="ATG Version changed mid log from -$OrigATGVersion- to -$ATGVersion- on $Date";
  }
}

sub Process_AircardVersion { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d\ +\-.* +Aircard Version: +(.*)/;
#print "\$StateLine :$StateLine:\n";

  my $Date="$1";
  my $TempVersion=$2;
#print "\$Date :$Date: \$TempVersion :$TempVersion:\n";

  $AircardVersion=$TempVersion if ( $AircardVersion eq "Undefined" );
  if ( $AircardVersion ne $TempVersion ) {
    $OrigAircardVersion=$AircardVersion;
    $AircardVersion=$TempVersion;
    push(@Altitudes, " $Date *** Error: Aircard Version changed mid log from $OrigAircardVersion to $TempVersion at $1");
    $Investigation{"AircardVersion"}="Aircard Version changed mid log from -$OrigAircardVersion- to -$TempVersion- on $Date";
  }

}


sub Process_ACID { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d\ +\-.* +ACID: ACM MAC Address: acidValFromScript +: +(.*)/;
#print "\$StateLine :$StateLine:\n";


  my $Date="$1";
  my $TempVersion=$2;
#print "\$Date :$Date: \$TempVersion :$TempVersion: \$ACID :$ACID:\n";

  $ACID=$TempVersion if ( $ACID eq "" );
  if ( $ACID ne $TempVersion ) {
    $OrigACID=$ACID;
    $ACID=$TempVersion;
    push(@Altitudes, " $Date *** Error: ACID Version changed mid log from $OrigACID to $TempVersion at $1");
    $Investigation{"AircardVersion"}="ACID Version changed mid log from -$OrigACID- to -$TempVersion- on $Date";
  }
}


sub Process_ACID2 { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d),\d\d\d\ +\-.*downloadFileFromACM\(\): ConfigurationModuleConstants.ACM_CONNECTED_STATUS : (.*)/;

  my $Date="$1";
  my $TempVersion=$2;
  #print "\$Date :$Date: \$TempVersion :$TempVersion: \$ACID :$ACID:\n";

  if ( $TempVersion eq "NOT_CONNECTED" ) {
    push(@Altitudes, " $Date *** FAILED TO RETRIEVE ACM STATUS!\n");
    $Errors{"ACM STATUS"}=" $Date *** FAILED TO RETRIEVE ACM STATUS!";
  }
}


sub Process_ATG_LINK {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.*(ATG LINK .*)$/;
  push(@Altitudes, "  ATG LINK Change : $1 -- $2");

}


sub Process_Ping_Test {
  # This version is 1.2.16.1
  my $StateLine=$_[0];

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +(.*)$/;
  push(@Altitudes, "    AAA Ping failed : $1");

}

sub Process_Ping_Test2 {
  # This version is 2.1.2
  my $StateLine=$_[0];

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +(.*)$/;
  push(@Altitudes, "    AAA Ping failed : $1");
}


 
sub Process_Ping_Latency_16_1 {
  # This version is 1.2.16.1
  my $StateLine=$_[0];
  my $PacketLoss; my $MinLat; my $AVGLat; my $MaxLat;
  my $Latencies;
  my $Date;

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +.*Ping result: (\d+)\% packet.* =  (.*)\/(.*)\/(.*)\/.* ms$/;

  if ( $StateLine =~ /100% packet loss/ ) {
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) .*Ping result:*/;
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "!!! 100% packet Loss!!!\n" if ( $opt_v );
    $Date=$1;
    $AVGPacketLoss += 100;
    $PingCount++;
    push(@Pings, "$Date, 100% Loss") if ( $opt_pings );
  } else {
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "*** Sub-100% packet Loss***\n" if ( $opt_v );
  # 1.2.16.1 - 2014-03-17 19:04:41,541 - Ping result: 0% packet loss time 0ms rtt min/avg/max/mdev = 78.065/78.065/78.065/0.000 ms
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) .*Ping result: (\d+)\%.* packet loss time .* = (.*)\/(.*)\/(.*)\/.* ms$/;
    
    $Date=$1;
    $PacketLoss=$2;
    $MinLat=$3;
    $AVGLat=$4;
    $MaxLat=$5;
    $AVGPacketLoss += $PacketLoss;
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "\$PacketLoss :$PacketLoss:\n" if ( $opt_v );

    $MinLatency=$MinLat if ( $MinLatency > $MinLat );
    $AVGLatency += $AVGLat;
    $MaxLatency=$MaxLat if ( $MaxLatency < $MaxLat );
    $PingCount++;
#    push(@Pings, "$StateLine") if ( $opt_pings );
    push(@Pings, "$Date, $PacketLoss, $MinLat, $AVGLat, $MaxLat") if ( $opt_pings );
  }

  print "\$AVGPacketLoss $AVGPacketLoss\n" if ( $opt_v );
  print "\$MinLatency $MinLatency\n" if ( $opt_v );
  print "\$AVGLatency $AVGLatency\n" if ( $opt_v );
  print "\$MaxLatency $MaxLatency\n" if ( $opt_v );
}
 
sub Process_Ping_Latency_2_1 {
  # This version is 1.2.16.1
  my $StateLine=$_[0];
  my $PacketLoss; my $MinLat; my $AVGLat; my $MaxLat;
  my $Latencies;
  my $Date;

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  if ( $StateLine =~ /100% packet loss/ ) {
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) .*Conducting AAA Ping Test:.*/;
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "!!! 100% packet Loss!!!\n" if ( $opt_v );
    $Date=$1;
    $AVGPacketLoss += 100;
    $PingCount++;
    push(@Pings, "$Date, 100% Loss") if ( $opt_pings );
  } else {
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "*** Sub-100% packet Loss***\n" if ( $opt_v );
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) .*Conducting AAA Ping Test: (\d+)\%.* packet loss time .*ms.* = (.*)\/(.*)\/(.*)\/.* ms$/;
    
    $Date=$1;
    $PacketLoss=$2;
    $MinLat=$3;
    $AVGLat=$4;
    $MaxLat=$5;
    $AVGPacketLoss += $PacketLoss;
    push(@Pings, "$Date, $PacketLoss, $MinLat, $AVGLat, $MaxLat") if ( $opt_pings );
    print "\$StateLine :$StateLine:\n" if ( $opt_v );

    $MinLatency=$MinLat if ( $MinLatency > $MinLat );
    $AVGLatency += $AVGLat;
    $MaxLatency=$MaxLat if ( $MaxLatency < $MaxLat );
    $PingCount++;
  }

  print "\$AVGPacketLoss $AVGPacketLoss\n" if ( $opt_v );
  print "\$MinLatency $MinLatency\n" if ( $opt_v );
  print "\$AVGLatency $AVGLatency\n" if ( $opt_v );
  print "\$MaxLatency $MaxLatency\n" if ( $opt_v );
}
 
 
sub Process_Ping_Threshold {
  my $StateLine=$_[0];

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  if ( $StateLine =~ /Thread-/ ) {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +\-\[Thread\-\d+\] +(.*)$/;
    push(@Altitudes, "    PING THRESHOLD: $1");
    $Errors{"PING_THRESHOLD"}="Ping Threshold Reached, aircard reset!";
  } else {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d) +\- +(.*)$/;
    push(@Altitudes, "    PING THRESHOLD: $1");
    $Errors{"PING_THRESHOLD"}="Ping Threshold Reached, aircard reset!";
  }
}

