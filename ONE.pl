#!/usr/bin/perl -w
$| = 1;

#
# This script reads the output file from /usr/local/bin/extract_one.pl and produces the following
#  1) Troubleshooting information for NetOps and TechSupport
#  2) TBD - XLS data output for Console data to load into EDW ( --xls flag )
#  3) GIS data? ( I'm already working with the data, why not? )


# Changes/ToDo
# 1) Get ATG Console data working for Troubleshooting output
# 2) Get ATG SM data working for Troubleshooting output
# 3) Get ATG Console data working for Troubleshooting output

use strict;
use diagnostics;
use Date::Calc qw(:all);
use Date::Manip;
use Class::Date;
use Text::CSV_XS;
my $csv = Text::CSV_XS->new( { binary => 1 } );

my $User=$ENV{"LOGNAME"};

# GetOpt
use vars qw( $opt_h $opt_v $opt_u $opt_f $opt_t $opt_all $opt_summary $opt_e $opt_temp $opt_fan $opt_flightstates $opt_auth $opt_stats $opt_start $opt_end $opt_pings $opt_dhcp $opt_values $opt_so $opt_devices $opt_month $opt_year $opt_SA $opt_Report $opt_Prov $opt_kml $opt_RR );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v u f=s e t all summary temp fan flightstates auth stats start=s end=s pings dhcp values so devices month=s year=s SA Report Prov kml RR");

my $GGTT_Enable=1;
my $Rand=int( rand( 20 ) );

$opt_RR=1 if ( $Rand == 1 );

# Make it easier
if ( $opt_all ) {
  $opt_e=1;
  $opt_stats=1;
  $opt_flightstates=1;
}
if ( $opt_summary ) {
  $opt_e=1;
  $opt_stats=1;
  $opt_flightstates=0;
}


if ( $opt_h ) {
  print "\n\n";
  print "Usage:  ONE.pl <options> -f <Log_File>\n"; print " -h = help (This screen)\n";
  print "\n";
  print "Required ( You need to use one of these so we know where to get the source date) : \n";
  print " -f <Log_File> : Specify a highlander log to read.\n";
  print " -t = Use TechSupport highlander.log ( /tmp/highlander-<user>.log )\n";
  print " -u = Use local user highlander.log ( ./highlander-<user>.log )\n";
  print "\n";
  print "Display Options: \n";
  print " --all = Show all options\n";
  print " --summary = Show summary options\n";
  print "   This is probably the one you want\n";
  print " -e = Show Display known \"error related lines\"\n";
  print " --flightstates = Show changes in flight states\n";
  print " --stats = Show ATG Stats/Versions\n";
  print " --kml = Generate Google-Earth KML file\n";
  print "\n";
  print "Options: \n";
  print " --values = Display hard coded values.\n";
  print "\n";
  print "Verbose Data Options: \n";
  print "   *** Due to verbosity, this is NOT included in --all ! \n";
  print " --temp = Show Verbose Temperature Readings\"\n";
  print " --fan = Show Verbose Fan RPM Readings\"\n";
  print " --auth = Show Authentication Status information\n";
  print " --pings = Show Ping Status information\n";
  print " --dhcp = Show ATG DHCP activity\n";
  print " --devices = Show when devices are discovered by the ATG\n";
  print " --SA = Show GGTT Short Analysis report for the acid\n";
  print " --Report = Show GGTT Report Analysis report for the acid\n";
  print " --Prov = Show Tail Provisioning Report for the Tail\n";
  print "\n";
  print "Date Options: \n";
  print " --start <Date> = Specify a starting date for processing.\n";
  print " --end <Date> = Specify an ending date for processing.\n";
  print " ** Date is in the format of 2014-02-03 19:00:10\n";
  print " ** The time portion of the Date is optional.\n";
  print "\n";
  print "\n\n\n";
  exit 0;
}

my $KML=1 if ( $opt_kml );

#
# Declare Variables
#
#
my $Verbose=$opt_v;
#
my $DateStart;
my $DateEnd;
#
# Defining values for min/max's as spesified by Engr.
# Fans
my $LockedFan=1318;  my $FanType=0;
my $MaxFan=0;  
my $FlightMaxFan=0;  
my $MaxSafeFan=9000;  
my $MinFan=900000;  
my $FlightMinFan=900000;  
my $MinSafeFan=5000;  
my $MaxFanString;
my $FlightMaxFanString;
my $MinFanString="";
my $FlightMinFanString="";
my $PingATGReset=0;  
my $FlightPingATGReset=0;  
my $LastPacketLoss=0;
my $LastLatency=99999;
my $PowerATGReset=0;  
my $FlightPowerATGReset=0;  
# Temp
my $MaxTemp=0;  
my $MaxSafeTemp=55; 
my $MaxTempString=""; 
my $MinXPOL=15; 
my $MinDRC=1800; 
my $TempErrors;
my $FlightMaxTemp=0;  
my $FlightMaxTempString=""; 
my $FlightTempErrors=0;
my $MaxFanErrors=0;
my $FlightMaxFanErrors=0;
my $MinFanErrors=0;
my $FlightMinFanErrors=0;
my $MaxFlightFanErrors=0;
my $FlightFanErrors=0;

#
# Define Valid Tail/Aircard verion matches as provided by Engr
my %Towers;
   &Define_Towers;
my %ValidPairs=&Define_Pairs;
my @DRCValues=(38.4,38.4,76.8,153.6,307.2,307.2,614.4,614.4,921.6,1228.8,1228.8,1843.2,2457.6,1536,3072,0,460.8,614.4,768,921.6,1075.2,1228.8,1843.2,2150.4,2457.6,3686.4,4300.8,4915.2);

#
my $Line;
my @LogLines;
my $Tail;
my %NetOpsNote; 
my $Loop;my %Auths; my %AuthAddr; my %FlightAuths; my %FlightAuthAddr;
my @Altitudes; 
#
#  This is used for calculating ASA/BSA, not state changes
my $Flight_State="";
#  This is used for calculating state changes, not ASA/BSA
my $FlightState="";
#  This is used for calculating state changes, not ASA/BSA
my $ATGLinkState="";
#  This is used for calculating state changes, not ASA/BSA
my $SBBLinkState="";
#
my $OpenCommand;
my $DebugMode;
my $AircardVersion="Undefined";
my $ATGVersion=0; 
my $ATGVersion_Shown="F";
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
my $GoodSINR=6;
my $SINRRatio=75;
my $LastDrift=0;
my $LastSINR="";
my $LastSINRCount=0;
my $CountMin=20;
my $SINRGood=0; 
my $SINRBad=0;
my $CoW="false";
my $CoWINIT="false";
my @Devices;
my $DateRange;
my $LastLat="undefined";
my $LastLon="undefined";
my $LastAlt="undefined";
my $LastCell="undefined";
my $LastSector="undefined";

# Ping Stats
my @Pings;
my $PingCount=0;
my $TotalPingCount=0;
my $AVGPacketLoss=0;
my $MinLatency=99999999;
my $AVGLatency=0;
my $sMaxLatency=0;
my $MaxLatency=0;
my $TotalMinLatency=999999999;
my $TotalAVGLatency=0;
my $TotalMaxLatency=0;
my @TotalDRC;
my @TotalSINR;
my $TotalDRC=0;
my $TotalSINR=0;

#
# X-Pol status tests
#
my $XPol=0;
my @XPol;
#
# We are using these for tracking errors and areas to investigate
#
my %Errors;
my %Investigation;
my %FlightErrors;
my $ACIDCHANGED;
my $AircardCHANGED;

#
# Maybe we can do something with the QoS logging?
#  * Severly limited with Rev-B due to Qualcom software
#
my %QoS; $QoS{6}="-1"; $QoS{7}="-1";
my $QoS_Fails=0;
my $Last_QoS_Fail;
my $Last_QoS_Fail_Test;
my $Last_Repeat;
my $Last_Repeat_Test;
my $Repeats;

#
# Stuff for KML
# 
my @AirlinkData;
my @RebootData;
my @GGTTData;
my @GGTTSMSData;
my @CallData;

#
# GGTT Parts
#
my $CallCount=0;
my $PopulateCallCount;

#
# 8K Specifics
#
my $Multiplexer_Version;
my %Aircard;


#
# This is used for the paste of the XPol.
#
# "e" is from Extract
my $eYear;
if ( $opt_year ) {
  $eYear=$opt_year;
}
my $eMonth;
if ( $opt_month ) {
  $eMonth=$opt_month;
} 


#
# We know that ATG's drift time, lets track the changes
#
my $TotalDays=0; my $TotalHours=0; my $TotalMins=0; my $TotalSecs=0;

# DHCP Related
my %DHCPActivity;
my %NonAuthorative; my $NonAuthorative; my $DHCPOFFER=0; my $DHCPREQ=0; my $DHCPACK=0;
my %FlightNonAuthorative; my $FlightNonAuthorative=0; my $FlightDHCPOFFER=0; my $FlightDHCPREQ=0; my $FlightDHCPACK=0;

#
# Installed SWKeys
#   Define known keys as inactive first
my $KeyCurrent=0;
#
# The Following defined at:
#   https://inside.gogoair.com/display/BP/Software+Keys
#
my %KeysNamed = (
    '100'=>'GogoBiz Voice',
    '101'=>'Gogo Text & Talk',
    '104'=>'ATG 5K Upgrade',
    '200'=>'UCS5000 - Voice Communication System',
    '201'=>'UCS5000 - In Air Vision',
    '202'=>'UCS5000 - WAN Management for Bearers',
    '203'=>'UCS5000 - Wan Optimization',
    '204'=>'UCS5000 - Moving Map',
    '205'=>'UCS5000 - Media ( NetJets Only )',
    '294'=>'UCS5000 - Moving Map ( 90 Day )',
    '291'=>'UCS5000 - In Air Vision ( 90 Day )',
    '300'=>'Cloud Surfer',
    '400'=>'ACARS',
    '401'=>'FANS Over Iridium ( FOI )'
  );
my %KeysInstalled;
my %KeysStart;
my %KeysEnd;
# Did a key go away? ( NetJets did )
my %KeysLastEntry;
my %KeysChanged;

if ( $opt_values ) {
  print "\n";
  print "The following values are hard coded for testing purpose:\n";
  print "\n";
  print "  Maximum Safe Operating Temperature : $MaxSafeTemp\n";
  print "  Maximum FAN RPM : $MaxSafeFan\n";
  print "  Minimum FAN RPM : $MinSafeFan\n";
  print "  Minimum SINR considered \"good\" : $GoodSINR\n";
  print "  Minimum SINR  Ratio : $SINRRatio\n";
  print "  Minimum X-Pol  : $MinXPOL\n";
  print "  Minimum DRC  : $MinDRC\n";
  print "\n";
  exit 0;
}


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
  $opt_f="/tmp/highlander-".$User.".log";
} 

if ( $opt_u ) {
  $opt_f="highlander-".$User.".log";
} 

if ( ! $opt_f ) {
  $opt_f="highlander.log";
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


#
# Get our Data
# 
open(INPUT, "$OpenCommand") || die "Can't open $opt_f :$?:\n";
while(<INPUT>) {
  chomp;
  $Line=$_;

  # Clean trash
  next if ( $Line =~  /^$/ );
  # Temp until we know if we need the non-date stamped lines
  next unless ( (  $Line =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+/ ) || ( $Line =~ /::NetOps Note:/ ) );

  push(@LogLines, $Line);
}

# Need these early
foreach $Line ( @LogLines ) {
  # Lets handle any extraction notes first:
  &Process_NetOps_Notes("$Line") if ( $Line =~ /::NetOps Note:/ );
  &Process_ACID("$Line") if ( $Line =~ /ACID: ACM MAC Address: acidValFromScript/ );
  &Process_ACID2("$Line") if ( $Line =~ /ACID: Value parsed successfully:/ );
}

#
# Merge in GGTT
#
&Get_GGTT if ( ( $GGTT_Enable ) && ( $ACID ));
@LogLines=sort(@LogLines);

foreach $Line ( @LogLines ) {
  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+)/;

  my $TestDate=$1;

  # Lets throw away known 'noise'
  # The ATG was just reset, we call that separately so these are trash
  next if ( $Line =~ /Coverage -> false FLIGHT STATE -> null$/ );
  next if ( $Line =~ /UNKNOWN_STATE$/ );

  #
  # Process ATG Console File Information
  #
  &Process_ATGVersion("$Line") if ( $Line =~ /ATG Application Version/ );
  &Process_ATG_retrieveFiles("$Line") if ( $Line =~ /FTP  Files in ACM are : acmFileList./ );
  &Process_ATG_Corrupt_Keys("$Line") if ( $Line =~ /keys.amf is corupted/ );
  &Process_Keys_Installed("$Line") if ( $Line =~ /SUCCESS, Software License Key added successfully/ );
  &Process_Keys_Deleted("$Line") if ( $Line =~ /SUCCESS, Software License Key deleted successfully/ );
  &Process_Keys_Uploaded("$Line") if ( $Line =~ /uploadFilesToACM: Uploading FilesList:/ );
  &Process_Device_Discovered("$Line") if ( $Line =~ /AMP:.*is discovered/ );
  &Process_Device_Notify("$Line") if ( $Line =~ /Notifying my device that .* is .* because/ );
  &Process_AircardVersion("$Line") if ( $Line =~ /Aircard Version:/ );
  &Process_CellOnWheels("$Line") if ( $Line =~ /CellOnWheels=/ );
  &Process_Authentication_Mesg("$Line") if ( $Line =~ /Authentication Message response/ );
  &Process_Coverage("$Line") if ( $Line =~ /ABS COVERAGE/ );
  &Process_Flight_State("$Line") if ( $Line =~ /Flight State \=\=\=/ );
  &Process_Flight_State_Change("$Line") if ( $Line =~ /Coverage.*FLIGHT/ );
  &Process_ATG_Link("$Line") if ( $Line =~ / ATG LINK \w+$/ );
  &Process_SBB_Link("$Line") if ( $Line =~ / SBB_LINK_\w+$/ );
  &Process_Ping_Test("$Line") if ( $Line =~ /Reset Count: 1 Ping failure: 5/ );
  &Process_Ping_Test2("$Line") if ( $Line =~ /ICMP ping to AAA server is failed/ );
  &Process_Ping_Latency_16_1("$Line") if ( $Line =~ /Ping result:/ );
  &Process_Ping_Latency_2_1("$Line") if ( $Line =~ /Conducting AAA Ping Test:./ );
  &Process_Ping_Threshold("$Line") if ( $Line =~ /PING_FAILURE_THRESHOLD...5/ );
  &Process_Signal_Strength("$Line") if ( $Line =~ /Signal Strength:/ );
#  &Process_Power_Reset("$Line") if ( $Line =~ /Last reset is due/ );
  &Process_Reset("$Line") if ( $Line =~ /rebootReason : / );
  &Process_Link_Down("$Line") if ( $Line =~ /atgLink[Down|Up]/ );
  &Process_Authentication_Status("$Line") if ( $Line =~ /Authentication Status/ );
  &Process_new_subnet_mask("$Line") if ( $Line =~ /new_subnet_mask/ );
  &Process_2_3_TimeError("$Line") if ( $Line =~ /rebootReason : System Time and GPS Time/ );
  &Process_Temp("$Line")  if ( $Line =~ /PCS Power Supply Temp/ );
  &Process_Fan_RPM("$Line") if ( $Line =~ /Fan is .* with rpm/ );
  # Process ATG SW Key Lines
  &Process_Key_Feature("$Line")  if ( $Line =~ /displyKeyValuesLogger\(\): keyValues.getFeature\(\)/ );
  &Process_Key_Feature_Status("$Line")  if ( $Line =~ /displyKeyValuesLogger\(\): keyValues.getKeyStatus/ );
  &Process_Key_Feature_Start("$Line")  if ( $Line =~ /displyKeyValuesLogger\(\): keyValues.getStartDate/ );
  &Process_Key_Feature_End("$Line")  if ( $Line =~ /displyKeyValuesLogger\(\): keyValues.getEndDate/ );
  # Did we write out the config files correctly?
  &Process_ACM_Status("$Line") if ( $Line =~ /downloadFileFromACM\(\): ConfigurationModuleConstants.ACM_CONNECTED_STATUS/ );
  &Process_ACM_File_Read("$Line") if ( $Line =~ /ACM: In DownLoad: listACMFiles: No. of Files in ACM is: / );
  &Process_ACM_FTP_Read("$Line") if ( $Line =~ /ACM: ConnectACM: Establish FTP Connection for 3 time/ );
  &Process_ACM_Read_Fail_2_1("$Line")  if ( $Line =~ /FTP Connection Successful with Configuration Module. No. of Files in ACM is :/ );
  # Get KML Data
  &Process_Airlink("$Line") if ( $Line =~ / Airlink: / );
  # Get GGTT Data
  &Process_GGTT("$Line") if ( $Line =~ / GGTT: / );
  &Process_GGTTSMS("$Line") if ( $Line =~ / GGTTSMS: / );
  # Capture Drift Changes
  &Process_DriftLine("$Line") if ( $Line =~ / Drift: / );

  #
  # 8K Specific Matches
  #
  &Process_8K_Temp("$Line")  if ( $Line =~ /ACPU board temperature/ );
  &Process_8K_Multiplexer_Version("$Line") if ( $Line =~ /Multiplexer Software Version/ );
  &Process_ACPUVersion("$Line") if ( $Line =~ /ACPU Application Version/ );
  &Process_AircardIP("$Line") if ( $Line =~ /Aircard Simple IP/ );

  #
  # Process QoS Lines
  #
  &Process_QoS("$Line") if ( $Line =~ /Flow for QoS Profile:/ );

  # These appear to be a false positive.  Disabling until we get details from BA Eng
#  &Process_QoS_Fail("$Line")  if ( $Line =~ /rule prio 0 protocol 800 reclassify is buggy packet dropped/ );
#  &Process_Last_Repeat("$Line")  if ( $Line =~ /ATG4K last message repeated .* times/ );

  #
  # Process ATG Messages File Information
  #
  #  Need Both of these?
  &Process_DHCP_REQUEST("$Line") if ( $Line =~ /DHCPREQUEST from/ );
  &Process_DHCP_REQUEST("$Line") if ( $Line =~ /DHCPREQUEST for/ );
  &Process_DHCP_OFFER("$Line") if ( $Line =~ /DHCPOFFER on/ );
  &Process_DHCP_DHCPACK("$Line") if ( $Line =~ /DHCPACK on/ );
}

&Calculate_Signals if ( $KML );
&Show_Flight_States if ( $opt_flightstates );
&Display_Stats if ( $opt_stats );
&Display_Errors if ( $opt_e );
&Display_Pings if ( $opt_pings );
&Display_Authentication_Status if ( $opt_auth );
&Display_DHCP if ( $opt_dhcp );
&Display_SA if ( $opt_SA );
&Display_Report if ( $opt_Report );
&Display_Provisioning if ( $opt_Prov );
&RickRoll if ( $opt_RR );
&Create_KML if ( $KML );

# Nothing to see below here, move along citizen. 
exit 0;




#################
# Sub Procs Here #
##################
sub Define_Pairs {

  #
  # Must escape *, - and +
  #
  my %ValidPairs = (
    "1.0.8-Rev-A"=>'Bigsky1737',
    "1.0.17-Rev-A"=>'Bigsky1737',
    "1.0.26-Rev-A"=>'Bigsky1737',
    "1.1.14-Rev-A"=>'Bigsky1737',
    "1.2.12-Rev-A"=>'Bigsky1737',
    "1.2.16-Rev-A"=>'Bigsky1737',
    "1.2.16.1-Rev-A"=>'Bigsky1737',
    #
    "2.0.1-Rev-A"=>'Bigsky1746',
    "2.0.2-Rev-A"=>'Bigsky1746',
    #
    "2.1.1-Rev-A"=>'Bigsky1746\+blob\-071911\+kernel\-071911\+fs\-071911',
    "2.1.1-Rev-B"=>'Aircard2.041',
    #
    "2.1.2-Rev-A"=>'Bigsky1746\+blob\-071911',
    "2.1.2-Rev-B"=>'Aircard2.041\+blob\-111412',
    #
    "2.2.1-Rev-A"=>'Bigsky1746\+blob\-071911',
    "2.2.1-Rev-B"=>'Aircard2.042\+blob\-100913',
    #
    "2.3.0-Rev-A"=>'Bigsky1746',
    "2.3.0-Rev-B"=>'Aircard2.042'
  );
  return( %ValidPairs );
}


sub Display_Stats {
  my $AircardType;
  my $tmp;

  $Tail="unknown" if ( ! $Tail );
  $ACID="unknown" if ( ! $ACID );
  print "\n";
  $DateEnd =~ m,(\d+)/(\d+)/(\d+),;
  my $DateEnd2=$1.$2.$3;
  print "Final Tail Log Stats:\n";
  print "  Flight Charts available at http://performance.aircell.prod/reports/catalog/index.cgi?rm=details&tail=$Tail&date=$DateEnd2 \n";
  print "  ATG Tail : $Tail\n";
  print "  ATG ACID : $ACID\n";
  print "  This tail is in Debug mode\n" if ( $DebugMode );
  print "      *** Originally was $OrigACID!!! ***\n" if ( $OrigACID );
  print "  ATG Version : $ATGVersion\n";
  print "      *** Originally was $OrigATGVersion!!! ***\n" if ( $OrigATGVersion );
  print "  Aircard Version : $AircardVersion\n";
  if ( $AircardVersion =~ /Bigsky/ ) {
    $AircardType="Rev-A"
  } elsif ( $AircardVersion =~ /Aircard2/ ) {
    $AircardType="Rev-B"
  } else {
    $AircardType="Unknown"
  }
  print "    Type: $AircardType\n" if ( $AircardType );
  print "      *** Originally was $OrigAircardVersion!!! ***\n" if ( $OrigAircardVersion );
  if ( $ATGVersion && $AircardVersion ) {
    my $TailCheck=$ATGVersion."-".$AircardType;
 
    if ( $ValidPairs{$TailCheck} ) {
      if ( "Bigsky1746+blob-071911+kernel-071911+fs-071911" !~ /Bigsky1746\+blob\-071911/ ) {
        print "Explicit doesn't match.\n";
      }
      if ( $AircardVersion !~ /$ValidPairs{$TailCheck}/ ) {
        print "    ** NOT A VALID ATG/Aircard pair!!!\n";
        $Investigation{"ATG-Aircard pair"}="** NOT A VALID ATG/Aircard pair!!!";
      } else {
        print "    This IS a valid ATG/Aircard pair.\n";
      }
    } else {
      if ( ( $AircardType ne "Unknown" ) && ( $ATGVersion ne "Unknown" ) ) {
        print "      No Pairs defined for this ATG Version Configuration.\n";
        print "      Please notify NetOps.\n";
        $Investigation{"ATG-Aircard pair"}="** No Pairs defined for this ATG Version Configuration.";
      }
    }
  } else {
    print "    Missing data, can't validate ATG/Aircard pairing\n";
  }
  print "  ATG Max Temp: $MaxTemp\n";
  if ( $MaxTemp < $MaxSafeTemp ) {
    print "    Temperature is within acceptable tolerances.\n";
  } else {
    print "    ** Temperature is NOT within acceptable tolerances.\n";
  }
  print "  Fan Type: ";
  if ( $FanType == 1 ) {
    print "*Locked.\n";
    print "    Minimum speed : $MinFan\n";
    print "    Maximum speed : $MaxFan\n";
    if ( ( $MinFan == $LockedFan ) && ( $MaxFan == $LockedFan ) ) {
      print "    Fan RPM is within acceptable tolerances.\n";
    } else {
      print "    ** Fan RPM is NOT within acceptable tolerances.\n";
    }
  } else {
    print "Tach.\n";
    print "    Minimum speed : $MinFan\n";
    print "    Maximum speed : $MaxFan\n";
    if ( ( $MinFan > $MinSafeFan ) && ( $MaxFan < $MaxSafeFan ) ) {
      print "    Fan RPM is within acceptable tolerances.\n";
    } else {
      print "    ** Fan RPM is NOT within acceptable tolerances.\n";
    }
    print "  Multiplexer Software Version : $Multiplexer_Version\n" if ( $Multiplexer_Version );
    print "  Aircard1 IP : $Aircard{1}\n" if ( $Aircard{1} );
    print "  Aircard2 IP : $Aircard{2}\n" if ( $Aircard{2} );
  }
 

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

    print "  Total DHCP Stats:\n";
    if ( $DHCPREQ > 0 ) {
      print "    Requests Seen: $DHCPREQ\n";
    } else {
      print "    No Requests Seen\n";
    }
    if ( $DHCPOFFER > 0 ) {
      print "    Offers Given: $DHCPOFFER\n";
    } else {
      print "    No Offers Given\n";
    }
    if ( $DHCPACK > 0 ) {
      print "    Offers Ack'd : $DHCPACK\n";
    } else {
      print "    No Offers Ack'd\n";
    }
    if ( scalar ( keys ( %Auths ) ) > 0 ) {
      print "  Total Unique IP Addresses Authenticated : ".scalar( keys (%AuthAddr) )."\n";
    } else {
      print "No IP's Authentication.\n";
    }
    if ( ( scalar ( keys ( %Auths ) ) < 1 ) && ( $DHCPREQ == 0 )) {
      print "  ** No DHCP Requests or IP's Authenticated.  Could be a CTR Issue.\n";
      $Investigation{"CTR"}="** No DHCP Requests or IP's Authenticated.  Could be a CTR Issue if not a deadhead flight.";
    }
  } else {
    print "No complete flights found.\n";
  }
  print "\n";
  &Display_XPol;
  print "\n";

  if ( @Devices ) {
    print "Devices Discovered:\n";
    foreach $Loop ( 0..$#Devices ) {
      print "  $Devices[$Loop]\n";
    }
    print "\n";
  }

  if ( scalar ( keys ( %NetOpsNote ) ) > 0 ) {
    print "NetOps Notes:\n";
    foreach $Loop ( sort ( keys ( %NetOpsNote ) ) ) {
      next if ( $Loop =~ /XPOL_Line/ );
      print "  $NetOpsNote{$Loop}\n";
    }
    print "\n";
  }

  if ( scalar ( keys ( %KeysInstalled ) ) > 0 ) {
    print "Software Keys:\n";
    foreach $Loop ( sort ( keys ( %KeysNamed ) ) ) {
      $KeysInstalled{$Loop}="Not Installed" if ( ! $KeysInstalled{$Loop} );
      print "  $KeysNamed{$Loop} is $KeysInstalled{$Loop}\n";
      print "    $KeysChanged{$Loop}\n" if ( $KeysChanged{$Loop} );
      print "    Key start date : $KeysStart{$Loop}\n" if (( $KeysStart{$Loop} ) && ( $KeysInstalled{$Loop} ne "Not Installed" ) );
      print "    Key end date : $KeysEnd{$Loop}\n" if ( ( $KeysEnd{$Loop} ) && ( $KeysInstalled{$Loop} ne "Not Installed" ) );
    }
    print "\n";
  } else {
    print "Software Keys:\n";
    print "  * No software keys installed.\n";
  }

  print "GGTT Data:\n";
  if ( @CallData ) {
    foreach $Loop ( sort @CallData ) {
      print "  $Loop\n";
    }
  } else {
    print "  No activity found in this time frame.\n";
  }
}


sub Process_NetOps_Notes {
  my $NoteLine=$_[0];
#     Extracting Tail 11286 Starting with 2015/04/01 10:00:00 through 2015/04/10 22:00:00 to /tmp/highlander-rharris.log 
  if ( $NoteLine =~ /Extracting Tail \w+ Starting/ ) {
    $NoteLine =~ /Extracting Tail (\w+) Starting with (.*) through (.*) to/;
   
    $Tail=$1;
    $DateStart=$2;
    $DateEnd=$3;
#print "\$NoteLine :$NoteLine:\n";
#print "\$Tail :$Tail:\n";
#print "\$DateStart :$DateStart:\n";
#print "\$DateEnd :$DateEnd:\n";
      $DateStart =~ s/ /_/g;
      $DateEnd =~ s/ /_/g;
    $DateRange=$DateStart."-".$DateEnd;
    $DateRange =~ s,/,,g;
    $DateRange =~ s,:,,g;
  } elsif ( $NoteLine =~ /Extracting logs for tail \w+/ ) {

    $NoteLine =~ /Extracting logs for tail (\w+)/;

    $Tail=$1;
  }
  $NoteLine =~ /(.*)::NetOps Note: (.*)/;
  my $Key=$1;
  my $Note=$2;
  $NetOpsNote{"$Key"}=$Note;
}


sub Display_XPol {
  my $PATH;
  my $XPStart; my $XPEnd;
  my $XPYear; my $XPMon;
  my $XPolScript="/usr/local/bin/xpol.pl";

  print "Total Average DRC for this Time Window:  ".sprintf("%.2f", $TotalDRC)."\n";
  print "Total Average SINR for this Time Window: ".sprintf("%.2f", $TotalSINR)."\n";
  print "\n";
  my $XPolError=0;
  my $DRCError=0;
  my $Loop;
  my $XPFiles;

  my $Mon=`date +%m`; chomp( $Mon );
  my $Day=`date +%d`; chomp( $Day );
  $Mon=$eMonth if ( $eMonth );

  my $Year=`date +%Y`; chomp( $Year );
  $Year=$eYear if ( $eYear );

  ( $XPStart, undef )=split('_', $DateStart);
  $XPStart =~ s,/,,g;
  ( $XPEnd, undef )=split('_', $DateEnd);
  $XPEnd =~ s,/,,g;
  $XPStart =~ /(\d\d\d\d)(\d\d)\d\d/;
  $XPYear=$1;
  $XPMon=$2;
  $PATH="/opt/log/atg/".$XPYear."/".$XPMon."/".$Tail."/sm/*";
  open(GETXPol, "/bin/ls -1 $PATH |");
  while(<GETXPol>) {
    chomp;
    my $File=$_;
    $File =~ /.*$Tail\.(\d\d\d\d-\d\d-\d\d)-\d\d.*SM.tar.gz/;
    my $Key=$1;
    $Key =~ s/-//g;
    if ( ( $XPStart < $Key ) && ( $XPEnd > $Key ) )  {
      $XPFiles .= " $File";
    }
  }
  if ( $XPFiles ) {
    open(GetXPol, "/bin/zcat $XPFiles | $XPolScript |") || die "Couldn't get X-Pol : $!";
    while(<GetXPol>) {
      chomp;
      next if ( /^Tail/ );
      if ( $_ ) {
        $_ =~ s/ +//g;
        @XPol=split(',', $_);
        $XPol=1;
      }
    }
  }
  close( GetXPol );

  if ( $XPol ) {
    print "X-Pol from $DateStart until $DateEnd:\n";
    print "  Tail: $XPol[0]  ATG Vers: $XPol[1] AvgDRC: $XPol[3]\n";
    print "  HFwd: $XPol[4]  HAft: $XPol[6] VFwd: $XPol[8]  VAft: $XPol[10]\n";
    for $Loop ( 4,6,8,10 ) {
      $XPol[$Loop] =~ /(\d+\.\d+)%/;
      my $Val=$1;
      $XPolError=1 if ( $Val < $MinXPOL );
    }
    if ( $XPolError ) {
      print "    ** X-Pol testing results are unacceptable!\n";
      $Investigation{"02-X-Pol"}="** X-Pol could be an issue!";
    } else {
      print "    X-Pol testing results are acceptable.\n"; 
    }
    print "  HFwd: $XPol[5]  HAft: $XPol[7] VFwd: $XPol[9]  VAft: $XPol[11]\n";
    for $Loop (5,7,9,11) {
      $XPol[$Loop] =~ /(\d+\.\d+)/;
      my $Val=$1;
      $DRCError=1 if ( $Val < $MinDRC );
    }
    if ( $DRCError ) {
      print "    ** DRC could be an issue!\n";
      $Investigation{"02-DRC"}="** DRC testing results are unacceptable!";
    } else {
      print "    DRC testing results are acceptable.\n";
    }
    print "\n";
  }

  my $TmpMonth;
  my $LastMonth;
  if ( $Day < 7 ) {
    $TmpMonth=ParseDate( "last month" );
    $TmpMonth =~ m/\d\d\d\d(\d\d)\d\d\d\d:.*/;
    $LastMonth = $1;
    print "** Not enough days in $Mons{$Mon} yet.  Running X-Pol against $Mons{$LastMonth}.\n";
    $Mon=$LastMonth;
  }

  $PATH="/opt/log/atg/".$Year."/".$Mon."/".$Tail."/sm/*";
  
  open(GetXPol, "/bin/zcat $PATH | $XPolScript |") || die "Couldn't get X-Pol : $!";
  while(<GetXPol>) {
    chomp;
    next if ( /^Tail/ );
    if ( $_ ) {
      $_ =~ s/ +//g;
      @XPol=split(',', $_);
      $XPol=1;
    }
  }
  close( GetXPol );

  if ( $XPol ) {
    print "X-Pol for $Year-$Mons{$Mon}:\n";
    print "  Tail: $XPol[0]  ATG Vers: $XPol[1] AvgDRC: $XPol[3]\n";
    print "  HFwd: $XPol[4]  HAft: $XPol[6] VFwd: $XPol[8]  VAft: $XPol[10]\n";
    for $Loop ( 4,6,8,10 ) {
      $XPol[$Loop] =~ /(\d+\.\d+)%/;
      my $Val=$1;
      $XPolError=1 if ( $Val < $MinXPOL );
    }
    if ( $XPolError ) {
      print "    ** X-Pol testing results are unacceptable!\n";
      $Investigation{"02-X-Pol"}="** X-Pol could be an issue!";
    } else {
      print "    X-Pol testing results are acceptable.\n"; 
    }
    print "  HFwd: $XPol[5]  HAft: $XPol[7] VFwd: $XPol[9]  VAft: $XPol[11]\n";
    for $Loop (5,7,9,11) {
      $XPol[$Loop] =~ /(\d+\.\d+)/;
      my $Val=$1;
      $DRCError=1 if ( $Val < $MinDRC );
    }
    if ( $DRCError ) {
      print "    ** DRC could be an issue!\n";
      $Investigation{"02-DRC"}="** DRC testing results are unacceptable!";
    } else {
      print "    DRC testing results are acceptable.\n";
    }
    print "      Execute this for a NAV friendly output:\n";
    print "      Month=$Mon; Year=$Year; zcat /opt/log/atg/\$Year/\$Month/$Tail/sm/* |  $XPolScript -t\n";
    print "      * Note you can change the value of Month and Year to run an older month than today\n";
  } else {
    print "      No X-Pol available.  Please run the command below by hand substituting the month you want.\n";
    print "      Month=$Mon; Year=$Year; zcat /opt/log/atg/\$Year/\$Month/$Tail/sm/* | $XPolScript\n";
    print "      * Note you can change the value of Month and Year to run an older month than today\n";
  }
}


sub Process_Signal_Strength {
  my $StateLine=$_[0];
  
  return if ( $ASA ne "T" ); 
  return if ( $Coverage ne "INSIDE ABS COVERAGE" );
  return if ( $StateLine =~ /[GOOD|BAD]/ );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+) +.*Signal Strength: +(.*)$/;

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

  push(@Altitudes, "    Signal Strength: $Date -- $SINR") if ( $SINR < 6 );
  $SINRGood++ if ( $SINR >= $GoodSINR ); 
  $SINRBad++ if ( $SINR < $GoodSINR ); 
}


sub Display_Errors {
  print "\n";
  print "Errors Found:\n"; 
  if ( $NetOpsNote{"0005-Console"} =~ /found 0 Console logs/ ) {
    print " ** No console logs found for this tail.  May need manual download.\n";
  }
  if ( ! keys ( %Errors ) ) {
    print " * No errors logged.\n";
  } else {
    foreach $Loop ( sort ( keys( %Errors ) ) ) {
      print "  $Errors{$Loop}\n";
    }
  }
  print "\n";
  print "Indicators to Investigate:\n"; 
  if ( $QoS_Fails > 10 ) {
    print "  Total ATG QoS Failure Complaints: $QoS_Fails ( TechSupp Ignore this for now. )\n";
  }
  if ( ! keys ( %Investigation ) ) {
    print " * Nothing identified.\n";
  } else {
    if ( scalar ( keys ( %KeysInstalled ) ) < 1 ) {
      print "  * No software keys installed.\n";
      print "    This could be a problem with the ACM, deleted keys or key file corruption.\n";
    }
    foreach $Loop ( sort ( keys ( %Investigation ) ) ) {
      print "  $Investigation{$Loop}\n";
    }
  }
  print "\n";
}


sub Display_Post_Flight_Stats {
  my $Date=$_[0];

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
  if ( scalar ( keys ( %FlightAuthAddr ) ) > 0 ) {
    push(@Altitudes, "      Unique IP Addresses Authenticated : ".scalar( keys (%FlightAuthAddr) ) );
  } else {
    push(@Altitudes, "      No IP Addresses Authenticated.");
  }
  if ( $FlightDHCPREQ > 0 ) {
    push(@Altitudes, "      DHCP requests this flight : ".$FlightDHCPREQ );
    $FlightDHCPREQ=0;
  } else {
    push(@Altitudes, "      No DHCP requests this flight.");
  }
  if ( $FlightDHCPOFFER > 0 ) {
    push(@Altitudes, "      DHCP offers given this flight : ".$FlightDHCPOFFER );
    $FlightDHCPOFFER=0;
  } else {
    push(@Altitudes, "      No DHCP offers given this flight.");
  }
  if ( $FlightPingATGReset > 0 ) {
    push(@Altitudes, "    ATG Was reset $FlightPingATGReset times due to Ping failures.");
    $FlightPingATGReset=0;
  }
  if ( $FlightPowerATGReset > 0 ) {
    push(@Altitudes, "    ATG Was reset $FlightPowerATGReset times due to power resets.");
    $FlightPowerATGReset=0;
  }
  push(@Altitudes, "    Flight Length : $days days, $hours hours, $mins minutes, $secs seconds");
  push(@Altitudes, "    Max Latency this time ASA: $MaxLatency");
  push(@Altitudes, "    AVG Latency this time ASA: $AVGLatency");
  push(@Altitudes, "    Min Latency this time ASA: $MinLatency");
  $TotalMinLatency = $MinLatency if ( $TotalMinLatency > $MinLatency );
  $TotalAVGLatency += $AVGLatency;
  $TotalMaxLatency = $MaxLatency if ( $TotalMaxLatency < $MaxLatency );
  $TotalPingCount += $PingCount;
  &Reset_Flight_Counters;
  if ( $FlightTempErrors > 0 ) {
    push(@Altitudes, "    * Flight Maximum temp exceeded $MaxSafeTemp $FlightTempErrors times with a maximum of $FlightMaxTemp");
  }
  if ( $SINRBad+$SINRGood == 0 ) {
    $Ratio=0;
  } else {
    $Ratio=($SINRGood/($SINRBad+$SINRGood))*100;
    $Ratio = sprintf "%.2f", $Ratio;
    push(@Altitudes, "    Signal Strenth Summary: $SINRGood Good entries while above altitude");
    push(@Altitudes, "    Signal Strenth Summary: $SINRBad   Bad entries while above altitude");
    push(@Altitudes, "    Very Bad SINR Ratio detected at $Date") if ( $Ratio < $SINRRatio );
    push(@Altitudes, "    Signal Strenth Ratio: $Ratio percent of the reported signal strength was >6 while ASA.");
    push(@Altitudes, " ");
  }
  $Investigation{"Ratio-$Date"}="Very Bad SINR Ratio detected at $Date" if ( $Ratio < $SINRRatio );
  push(@Altitudes, " ");
}


sub Reset_Flight_Counters {
  $MinLatency=9999999;
  $AVGLatency=0;
  $MaxLatency=0;
  $PingCount=0;
  $FlightTempErrors=0;
  $FlightMaxTemp=0;
  $SINRGood=0;
  $SINRBad=0;
  undef( %FlightAuths );
  undef( %FlightAuthAddr );
  $FlightDHCPREQ=0;
  $FlightDHCPOFFER=0;
}

sub Display_Pings {
  print "\n";
  print "Pings Recorded :\n"; 
  foreach $Loop (0..$#Pings) {
   print "  $Pings[$Loop]\n";
  }
  print "\n";
}


sub Display_DHCP {
  print "\n";
  print "DHCP Activity Recorded :\n"; 
  foreach $Loop (sort ( keys ( %DHCPActivity ) ) ) {
   print "  $DHCPActivity{$Loop}\n";
  }
  print "\n";
}


sub Display_SA {
  print "\n";

  if ( $ACID eq "unknown" ) {
    print "GGTT report not availble, no ACID found in the logs.\n";
    return;
  }

  print "GGTT (Accuroam) Activity Short Analysis :\n"; 

  my $Mon=`date +%m`; chomp( $Mon );
  $Mon=$eMonth if ( $eMonth );
  my $Year=`date +%Y`; chomp( $Year );
  $Year=$eYear if ( $eYear );
  my $ALDate=$Year.$Mon;

  print "  Data for $ACID for the month of $Mon\n";
  
  open(ACCUROAM, "/usr/local/bin/AccuLogs.pl --SA -A $ACID -F $ALDate |");
  while(<ACCUROAM>) {
    chomp;
    print "    $_\n";
  }
  close(ACCUROAM);
  print "\n";
}
 

sub Display_Report {
  print "\n";

  if ( $ACID eq "unknown" ) {
    print "GGTT report not availble, no ACID found in the logs.\n";
    return;
  }

  print "GGTT (Accuroam) Activity Short Analysis :\n"; 

  my $Mon=`date +%m`; chomp( $Mon );
  $Mon=$eMonth if ( $eMonth );
  my $Year=`date +%Y`; chomp( $Year );
  $Year=$eYear if ( $eYear );
  my $ALDate=$Year.$Mon;

  print "  Data for $ACID for the month of $Mon\n";
  
  open(ACCUROAM, "/usr/local/bin/AccuLogs.pl -R -A $ACID -F $ALDate |");
  while(<ACCUROAM>) {
    chomp;
    print "    $_\n";
  }
  close(ACCUROAM);
  print "\n";
}


sub Display_Provisioning {

  print "\n";
  print "Tail Provisioning Results for $Tail :\n"; 
  
  open(PROVISIONING, "/usr/local/bin/Check_Tail_Provisioning.pl -T $Tail |");
  while(<PROVISIONING>) {
    chomp;
    print "  $_\n";
  }
  close(PROVISIONING);
  print "\n";
}


sub Process_aircardState {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+) +.* aircardState : +(.*)$/;

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
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+) +.* (AMP:.*)$/;
    if ( $FlightState ne $2 ) {
      $FlightState=$2;
      push(@Altitudes, "FlightState Change : $1 -- $2");
    }
  } elsif ( $StateLine =~ /Coverage/) {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+) +.* Coverage .* FLIGHT STATE -> (.*)$/;
    if ( $FlightState ne $2 ) {
      $FlightState=$2;
      push(@Altitudes, "FlightState Change : $1 -- $2");
    }
  }
}


sub Process_Flight_State {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) +.*\> (\w+)$/;
  my $Date=$1;
  my $NewState=$2;

  if (( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" ) && ( $NewState eq "ABOVE_SERVICE_ALTITUDE" )){
    $ASA="T";
    $ASATime="$Date";
    push(@Altitudes, "-------------------------");
    push(@Altitudes, ": Starting a new flight :");
    push(@Altitudes, "-------------------------");
    &Reset_Flight_Counters;
  }

  return if ( $ASA ne "T" );

  if ( $Flight_State !~ $NewState ) {
    print "Pushing $1 -- $2\n" if ( $Verbose );
    push(@Altitudes, "FlightState Change : $1 -- $2 ASA=$ASA Flight_Stat=$Flight_State NewState=$NewState");
    # We just went BSA, Lets do post-flight stats
    if (( $Flight_State eq "ABOVE_SERVICE_ALTITUDE" ) && ( $NewState ne "ABOVE_SERVICE_ALTITUDE" )){
      push(@Altitudes, "-------------------------");
      &Display_Post_Flight_Stats($Date);
      push(@Altitudes, "");
    }
    $Flight_State=$2;
  }

}


sub Process_Coverage {
  my $StateLine=$_[0];

  return if ( $ASA ne "T" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .* (\w+SIDE ABS COVERAGE)/;
  if ( $Coverage !~ $2 ) {
    $Coverage=$2;
    print "Pushing $1 -- $2\n" if ( $Verbose );
    push(@Altitudes, "  Coverage Change : $1 -- $2");
  }
  $Investigation{"01-OUTSIDE Coverage"}="Flight was OUTSIDE GoGo network coverage" if ( $Coverage =~ /OUTSIDE/ );

}


sub Process_Power_Reset {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .* (Last reset is due.*)/;
  my $Time=$1;
  my $Reset=$2;

  if ( $Coverage !~ $Reset ) {
    $Coverage=$Reset;
    print "Pushing $Time -- $Reset\n" if ( $Verbose );
    push(@Altitudes, "  * Power Reset        : $Time -- $Reset");
    $Flight_State="NULL";
    $PowerATGReset++;
    $FlightPowerATGReset++;
    $LastLat="Undefined" if ( !$LastLat );
    $LastLon="Undefined" if ( !$LastLon );
    $LastAlt="Undefined" if ( !$LastAlt );
    $LastCell="Undefined" if ( !$LastCell );
    $LastSector="Undefined" if ( !$LastSector );
    my $RebootDataLine = "$Time PowerReset: Latitude $LastLat, Longitude $LastLon, Altitude $LastAlt, LastCell $LastCell, LastSector $LastSector, LastASA $ASA";
    $Investigation{"PowerReset"}="ATG was reset $PowerATGReset times due to $Reset.";
    if ( $Reset =~ /DEBUG_HW_RST/ ) {
      $Investigation{"PowerReset"}="  * This is the result of a user using a Discrete to reset the unit.";
      $RebootDataLine .= ", Reason: This is the result of a user using a Discrete to reset the unit.";
    }
    push(@RebootData, $RebootDataLine);
  }
}


sub Process_Reset {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .*rebootReason : (.*) : updat/;
  my $Time=$1;
  my $Reset=$2;

  if ( $Coverage !~ $Reset ) {
    $Coverage=$Reset;
    print "Pushing $Time -- $Reset\n" if ( $Verbose );
    push(@Altitudes, "  * Power Reset        : $Time -- $Reset");
    $Flight_State="NULL";
    $PowerATGReset++;
    $FlightPowerATGReset++;
    $LastLat="Undefined" if ( !$LastLat );
    $LastLon="Undefined" if ( !$LastLon );
    $LastAlt="Undefined" if ( !$LastAlt );
    $LastCell="Undefined" if ( !$LastCell );
    $LastSector="Undefined" if ( !$LastSector );
    my $RebootDataLine = "$Time PowerReset: Latitude $LastLat, Longitude $LastLon, Altitude $LastAlt, LastCell $LastCell, LastSector $LastSector, LastASA $ASA";
    $Investigation{"ATG PowerReset"}="ATG was reset $PowerATGReset times due to $Reset.";
    push(@RebootData, $RebootDataLine);
  }
}


sub Process_CellOnWheels {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+).*CellOnWheels=(\w+).*/;
  
  my $Date=$1;

  $CoW=$2;

  if (( $StateLine =~ /System Configurations being initialised/ ) && ( $CoW eq "true" )) {
    $CoWINIT="true";
    print "Pushing $Date -- CoW Status : $CoW\n" if ( $Verbose );
    push(@Altitudes, "  *** ATG Initialized with CellOnWheels Status! : $Date -- $CoW");
    $Errors{"CoW-$Date"}="*** ATG Initialized with ATG was in CellOnWheels at $Date";
  } else {
    if ( $CoW eq "true" ) {
      print "Pushing $Date -- CoW Status : $CoW\n" if ( $Verbose );
      push(@Altitudes, "  CellOnWheels Status! : $Date -- $CoW");
    }
  }
}


sub Process_QoS {
#  return;
  my $StateLine=$_[0];
  my $Date; my $Chan; my $Stat; my $StatVal;

  if ( $StateLine =~ /RevA/ ) { 
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+).*Flow for QoS Profile: +(\d) +is: (.*)/;
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
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+).*(NCS: +UnifyConnection:.*)/;
  if ( $Coverage !~ $2 ) {
    $Coverage=$2;
    print "Pushing $1 -- $2\n" if ( $Verbose );
    push(@Altitudes, "Link Change        : $1 -- $2");
  }
}


sub Process_Authentication_Mesg {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*Authentication Message response +(.*)/;
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


sub Process_new_subnet_mask {
  my $StateLine=$_[0];
  my $Date;
  my $Mask;

  print "\$StateLine :$StateLine:\n" if ( $Verbose );

  if ( $StateLine =~ /new_subnet_mask\.+$/ ) {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*SBB-DHCP INFO: /;
    return;
  } else {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*SBB-DHCP INFO: new_subnet_mask\.+(.*)/;
    $Date="$1";
    $Mask=$2;
    $Date =~ s/\,\d+//;
  }

  return if ( $Mask eq "255.255.255.0" );

  push(@Altitudes, " $Date *** Improper Subnet mask $Mask");
  $Errors{"IPConflict-$Mask"}="$Date *** Improper Subnet mask $Mask";
  $Errors{"IPConflict-$Mask.1"}="  ** NON-Authorative subnet provided by SBB or third party system, causing a dns server issues, please identify the SBB OR third party system for proper course of action.";
}


sub Process_unexpected_RCODE {
  my $StateLine=$_[0];

  print "\$StateLine :$StateLine:\n" if ( $Verbose );
  return if ( $StateLine =~ /192.168.5.1\#53$/ );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*unexpected RCODE .* resolving '.*': (.*)#53/;

  my $Date="$1";
  my $Error=$2;

  push(@Altitudes, " $Date *** Error: IP Conflict with $Error");
  $Errors{"IPConflict-$Error"}="$Date *** Error: IP Conflict with $Error";
  $Errors{"IPConflict-$Error.1"}="  ** Check for a SBB or 3rd Party router with a bad IP in the 10.X space.  Move it to 192.168.5.X";
}


sub Process_2_3_TimeError {
  my $StateLine=$_[0];

  return if ( $FlightState ne "ABOVE_SERVICE_ALTITUDE" );

  print "\$StateLine :$StateLine:\n" if ( $Verbose );
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*TIME: rebootReason : System Time and GPS Time difference EXCEED the threshold/;

  my $Date="$1";

  push(@Altitudes, " $Date *** 2.3 Error: Time Drift was too great, Reset the ATG.");
  $Errors{"$Date - 2.3Drift"}=" $Date *** 2.3 Error: Time Drift was too great and Reset the ATG.";
  $Errors{"$Date - 2.3Drift.1"}=" ** ARINC 429 GPS time differs from the internal ATG clock time by more than 10 mins.";
  $Errors{"$Date - 2.3Drift.2"}=" ** This causes the service to be interrupted and / or the GGTT/GGBV keys of the unit to remain inactive";
  $Errors{"$Date - 2.3Drift.3"}=" ** Check GPS/FMS alignment.";
}


sub Process_Authentication_Status {
  my $Line=$_[0];
  print "\$Line :$Line:\n" if ( $Verbose );
  $Line =~ /(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d+).*Authentication Status for +(\d+\.\d+\.\d+\.\d+)\/.*: *(\w+)$/;
#2015-02-02 19:01:13,118 Console: - Authentication Status for 172.19.134.15/root@aircellmaintenance.com: Success
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


sub Display_Authentication_Status {
  print "\n";
  print "Authentication Stats:\n";
  foreach $Loop ( sort ( keys( %Auths ) ) ) {
    print " $Loop\n";
  }
  print "\n";
}


sub Process_Temp {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d) (\d\d:\d\d:\d\d,\d+).*PCS Power Supply Temperature +(.*)$/;
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


sub Process_8K_Temp {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).*ACPU board temperature: +(.*)$/;
  my $Date=$1;
  my $Temp=$2;
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


sub Process_Fan_RPM {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+).* Fan is .* with rpm (.*) *$/;

  $TimeStamp=$1;
  $State=$2;

  print "$TimeStamp - $State\n" if ( $opt_fan );

  if ( $State == $LockedFan ) {
    $FanType=1;
  } 

  if  ( $State > $MaxFan ) {
    $MaxFan=$State;
    $MaxFanString="RPM $MaxFan recorded at $TimeStamp.";
    $FlightMaxFan=$State;
    $FlightMaxFanString="RPM $MaxFan recorded at $TimeStamp";
    print "\$MaxFanString :$MaxFanString:\n" if ( $Verbose );
  }
  if  ( $State < $MinFan ) {
    $MinFan=$State;
    $MinFanString="RPM $State recorded at $TimeStamp";
    $FlightMinFan=$State;
    $FlightMinFanString="RPM $State recorded at $TimeStamp";
    print "\$MinFanString :$MinFanString:\n" if ( $Verbose );
  }

  if ( $State > $MaxSafeFan ) {
    $FlightMaxFanErrors++;
    $MaxFanErrors++;
    $Errors{"MaxFanRPM"}="Max Fan Error : $MaxFanString  Fan RPM above $MaxSafeFan rpm $MaxFanErrors times.";
    $FlightErrors{"MaxFanRPM"}="Max Fan Error : $FlightMaxFanString  Fan RPM above $MaxSafeFan rpm $FlightMaxFanErrors times.";
  } elsif ( $State < $MinSafeFan ) {
    $FlightMinFanErrors++;
    $MinFanErrors++;
    $Errors{"MinFanRPM"}="Min Fan Error : $MinFanString  Fan RPM below $MinSafeFan rpm $MinFanErrors times.";
    $FlightErrors{"MinFanRPM"}="Min Fan Error : $FlightMinFanString  Fan RPM below $MinSafeFan rpm $FlightMinFanErrors times.";
  }
}


sub Process_ACPUVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d,\d+) .* ACPU Application Version +: +(\d+\.\d+\.\d+)/;

  my $Date="$1";
  $ATGVersion=$2;

}


sub Process_AircardIP {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d,\d+) Console: - Aircard(\d+): Aircard Simple IP : (.*)$/;

  my $Date="$1";
  $Aircard{$2}=$3;

}


sub Process_ATGVersion {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d,\d+) .*ATG Application Version +: +(.*)$/;

  my $Date="$1";
  my $TempVersion=$2;

  push(@Altitudes, "    ATG Version : $1 -- $2") if ( $ATGVersion_Shown eq "F" );
  $ATGVersion_Shown="T" if ( $ATGVersion_Shown eq "F" );

  $ATGVersion=$TempVersion if ( $ATGVersion eq "0" );
  if ( $ATGVersion ne $TempVersion ) {
    $OrigATGVersion=$ATGVersion;
    push(@Altitudes, " $Date *** Error: ATG Version changed mid log from $OrigATGVersion to $TempVersion at $1");
    $Investigation{"ATGVersion $Date"}="ATG Version changed mid log from -$OrigATGVersion- to -$TempVersion- on $Date";
    $ATGVersion=$TempVersion;
  }
}


sub Process_8K_Multiplexer_Version {
  my $Line=$_[0];

  $Line =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d,\d+) .*Multiplexer Software Version : +(.*)$/;

  my $Date="$1";
  $Multiplexer_Version=$2;
}


sub Process_AircardVersion { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).* +Aircard Version: +(.*)/;

  my $Date=$1;
  my $TempVersion=$2;

  $TempVersion="Unknown" if ( $TempVersion eq "" );

  $AircardVersion=$TempVersion if ( $AircardVersion eq "Undefined" );
  if ( $AircardVersion ne $TempVersion ) {
    $OrigAircardVersion=$AircardVersion;
    $AircardCHANGED="*** Error: Aircard Version changed mid log from $OrigAircardVersion to $TempVersion at $1";
    push(@Altitudes, " $Date *** Error: Aircard Version changed mid log from $OrigAircardVersion to $TempVersion at $1");
    $Investigation{"AircardVersion"}="Aircard Version changed mid log from \"$OrigAircardVersion\" to \"$TempVersion\" on $Date";
    $AircardVersion=$TempVersion;
  }

}


sub Process_ACID { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*ACID: ACM MAC Address: acidValFromScript +: +(.*)/;

  my $Date="$1";
  my $TempVersion=$2;

#print "Process_ACID :$StateLine:\n";

  $ACID=$TempVersion if ( $ACID eq "" );
  if ( $ACID ne $TempVersion ) {
    $OrigACID=$ACID;
    $ACIDCHANGED="*** Error: ACID Version changed mid log from $OrigACID to $TempVersion at $1";
    push(@Altitudes, " $Date *** Error: ACID Version changed mid log from $OrigACID to $TempVersion at $1");
    $Investigation{"AircardVersion"}="ACID Version changed mid log from -$OrigACID- to -$TempVersion- on $Date";
    $ACID=$TempVersion;
  }
}


sub Process_ACID2 { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*ACID: Value parsed successfully: +(.*)/;

  my $Date="$1";
  my $TempVersion=$2;

  $ACID=$TempVersion if ( $ACID eq "" );
  if ( $ACID ne $TempVersion ) {
    $OrigACID=$ACID;
    $ACIDCHANGED="*** Error: ACID Version changed mid log from $OrigACID to $TempVersion at $1";
    push(@Altitudes, " $Date *** Error: ACID Version changed mid log from $OrigACID to $TempVersion at $1");
    $Investigation{"AircardVersion"}="ACID Version changed mid log from -$OrigACID- to -$TempVersion- on $Date";
    $ACID=$TempVersion;
  }
}


sub Process_ACM_Status { 
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d +\d\d:\d\d:\d\d\,\d+).*downloadFileFromACM\(\): ConfigurationModuleConstants.ACM_CONNECTED_STATUS : (.*)/;

  my $Date="$1";
  my $ACM_Status=$2;

  if ( $ACM_Status ne "CONNECTED" ) {
    push(@Altitudes, " $Date *** ACM DID NOT REPORT CONNECTED!\n");
    $Investigation{"ACM STATUS"}=" $Date *** ACM DID NOT REPORT CONNECTED!";
  }
}


sub Process_ATG_Link {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+).*(ATG LINK \w+)$/;
  if ( $ATGLinkState ne $2 ) {
    $ATGLinkState=$2;
    push(@Altitudes, "  ATG LINK Change : $1 -- $2");
  }

}


sub Process_SBB_Link {
  my $Line=$_[0];
  my $TimeStamp;
  my $State;

  $Line =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d\d\d).*(SBB_LINK_.*)$/;

  $TimeStamp=$1;
  $State=$2;

  if ( $SBBLinkState ne $2 ) {
    $SBBLinkState=$2;
    push(@Altitudes, "  SBB Status : $1 -- $2");
  }

}


sub Process_Ping_Test {
  # This version is 1.2.16.1
  my $StateLine=$_[0];

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) +(.*)$/;
  my $Date=$1;
  my $PingStat=$2;
  push(@Altitudes, "    AAA Ping failed 1 : $PingStat");
  push(@Altitudes, "    AAA Ping failed 2 : $Date - $PingStat");
  $LastPacketLoss="100%";
  $LastLatency=99999;
}

sub Process_Ping_Test2 {
  # This version is 2.1.2
  my $StateLine=$_[0];

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) +(.*)$/;
  my $Date=$1;
  my $PingStat=$2;
  push(@Altitudes, "    AAA Ping failed 2 : $Date - $PingStat");
  $LastPacketLoss="100%";
  $LastLatency=99999;
}


 
sub Process_Ping_Latency_16_1 {
  # This version is 1.2.16.1
  my $StateLine=$_[0];
  my $PacketLoss; my $MinLat; my $AVGLat; my $MaxLat;
  my $Latencies;
  my $Date;

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) +.*Ping result: (\d+)\% packet.* =  (.*)\/(.*)\/(.*)\/.* ms$/;

  if ( $StateLine =~ /100% packet loss/ ) {
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .*Ping result:*/;
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "!!! 100% packet Loss!!!\n" if ( $opt_v );
    $Date=$1;
    $AVGPacketLoss += 100;
    $PingCount++;
    $LastPacketLoss="100%";
    $LastLatency="99999";
    push(@Pings, "$Date, 100% Loss") if ( $opt_pings );
  } else {
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "*** Sub-100% packet Loss***\n" if ( $opt_v );
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .*Ping result: (\d+)\%.* packet loss time .* = (.*)\/(.*)\/(.*)\/.* ms$/;
    
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
    $LastPacketLoss=$PacketLoss;
    $LastLatency=$AVGLat;
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
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .*Conducting AAA Ping Test:.*/;
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "!!! 100% packet Loss!!!\n" if ( $opt_v );
    $Date=$1;
    $AVGPacketLoss += 100;
    $PingCount++;
    push(@Pings, "$Date, 100% Loss") if ( $opt_pings );
    $LastLatency="99999";
  } else {
    print "\$StateLine :$StateLine:\n" if ( $opt_v );
    print "*** Sub-100% packet Loss***\n" if ( $opt_v );
    $StateLine =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) .*Conducting AAA Ping Test: (\d+)\%.* packet loss time .*ms.* = (.*)\/(.*)\/(.*)\/.* ms$/;
    
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
    $LastLatency=$AVGLat;
  }
#print "\$StateLine :$StateLine:\n";
#print "\$LastPacketLoss :$LastPacketLoss:\n";
#print "\$LastLatency :$LastLatency:\n";

  print "\$AVGPacketLoss $AVGPacketLoss\n" if ( $opt_v );
  print "\$MinLatency $MinLatency\n" if ( $opt_v );
  print "\$AVGLatency $AVGLatency\n" if ( $opt_v );
  print "\$MaxLatency $MaxLatency\n" if ( $opt_v );
}
 
 
sub Process_Ping_Threshold {
  my $StateLine=$_[0];

  return if ( $Flight_State ne "ABOVE_SERVICE_ALTITUDE" );
  return if ( $StateLine =~ /HSS: ping/ );

  if ( $StateLine =~ /Thread-/ ) {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+) +\-\[Thread\-\d+\] +(.*)$/;
    push(@Altitudes, "    PING THRESHOLD: $1");
    $Errors{"PING_THRESHOLD"}="Ping Threshold Reached, aircard reset ( $PowerATGReset times )!";
  } else {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,\d+).*PING_FAILURE_THRESHOLD.+(\d*)$/;
    push(@Altitudes, "    PING THRESHOLD: $1");
    $Errors{"PING_THRESHOLD"}="Ping Threshold Reached, aircard reset! ( $PowerATGReset times )";
  }
}



sub Process_DHCP_REQUEST {
  my $StateLine=$_[0];
  my $Date; my $Request; my $ReqServer; my $Source; my $Gateway; my $Key; 

  if ( $StateLine =~ /ignored/ ) {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*DHCPREQUEST for (.*) from (.*) via (.*): ignored.*/;

    $Date=$1;
    $Request=$2;
    $Source=$3;
    $Gateway=$4;
    $Key=$Date."-".$Source;

    $NonAuthorative++;
    $FlightNonAuthorative++;
    $NonAuthorative{$Source}=1;
    $FlightNonAuthorative{$Source}=1;
    #$Investigation{"MAC ADDR : $Source"}="$Source requested an IP ( $Request ) and was ignored as non authorative. ***Tech Support ignore this line, it is experimental!!***";
    #push(@Altitudes,"  * $Date $Source requested an IP ( $Request ) and was ignored as non authorative. ***Tech Support ignore this line, it is experimental!!***");
    #$DHCPActivity{$Key}="  * $Date $Source requested an IP ( $Request ) and was ignored as non authorative. ***Tech Support ignore this line, it is experimental!!***";
    return;
  } else {
    $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*DHCPREQUEST for (.*) from (.*) via (.*)/;
    $Date=$1;
    $Request=$2;
    $Gateway=$3;
    $Source=$4;
    $Key=$Date."-".$Source;
    $DHCPREQ++;
    $FlightDHCPREQ++;
    $DHCPActivity{$Key}="  * $Date $Source Requested $Request via $Gateway";
  }
}


sub Process_DHCP_OFFER {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*DHCPOFFER on (\d+\.\d+\.\d+\.\d+) to (.*) via (.*)/;

  my $Date=$1;
  my $Offer=$2;
  my $Source=$3;
  my $Gateway=$4;
  my $Key=$Date."-".$Source;
  $DHCPOFFER++;
  $FlightDHCPOFFER++;
  $DHCPActivity{$Key}="  * $Date $Source Offered $Offer via $Gateway";
}


sub Process_DHCP_DHCPACK {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*DHCPACK on (.*) to (.*) via (.*)/;

  my $Date=$1;
  my $Offer=$2;
  my $Source=$3;
  my $Gateway=$4;
  my $Key=$Date."-".$Source;
  $DHCPACK++;
  $FlightDHCPACK++;
  $DHCPActivity{$Key}="  * $Date $Source Accepted $Offer via $Gateway";
}


sub Process_Keys_Installed {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*/;

  my $Date=$1;

  push(@Altitudes,"  $Date Software License Key Installed");

  if ( ! $Errors{"License_Key_Installed-01"} ) {
    $Errors{"License_Key_Installed-01"}="$Date Software License Keys Installed";
  }
}


sub Process_Keys_Deleted {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*/;

  my $Date=$1;

  push(@Altitudes,"  $Date Software License Key Deleted");

  if ( ! $Errors{"License_Key_Deleted-01"} ) {
    $Errors{"License_Key_Deleted-01"}="$Date Software License Keys Deleted";
  }
}


sub Process_Keys_Uploaded {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*Uploading FilesList: \[(.*)\]/;

  my $Date=$1;
  my $Files=$2;

  push(@Altitudes,"  $Date Software License Key Uploaded");

  if ( ! $Investigation{"Keys_Uploaded-01"} ) {
    $Investigation{"Keys_Uploaded-01"}="$Date Software License Keys Uploaded";
  }
}


sub Process_ATG_Corrupt_Keys {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*/;

  my $Date=$1;

  push(@Altitudes,"  $Date keys.amf is reported corrupted");

  if ( ! $Errors{"Corrupt keys.amf-01"} ) {
    $Errors{"Corrupt keys.amf-01"}="$Date Keys.amf is corrupted";
  }
}


sub Process_ATG_retrieveFiles {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*FTP  Files in ACM are : acmFileList : \[(.*)\]/;

  my $Date=$1;
  my $ConfigFiles=$2;

  push(@Altitudes,"  Retrieved ACM Config files: $ConfigFiles");
  if ( $ConfigFiles !~ /acpu.conf/ ) {
    $Errors{"ATG_Config-01"}="Did not see acpu.conf in the ACM configuration files.";
    $Errors{"ATG_Config-99"}="** Possible ATG Configuration Problem or ACM was replaced.";
  }
  if ( $ConfigFiles !~ /keys.amf/ ) {
    $Errors{"ATG_Config-02"}="Did not see keys.amf in the ACM configuration files.";
    $Errors{"ATG_Config-99"}="** Possible ATG Configuration Problem or ACM was replaced.";
  }
}


sub Process_ACM_FTP_Fail {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) .*ConnectACM: Establish FTP Connection for 3 time/;


  my $Date=$1;

  push(@Altitudes,"  ACM FTP Failure!");
  $Errors{"ACMReadFail"}="ATG was unable to FTP to the ACM!";
  $Errors{"ACMReadFail-01"}="  * Found at $Date";
  $Errors{"ACMReadFail-02"}="  * This COULD mean a connectivty or ACM failure.";
}


sub Process_ACM_Read_Fail_2_1 {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) .* *FTP Connection Successful with Configuration Module. No. of Files in ACM is :(.*)/;


  my $Date=$1;
  my $Files=$2;

  if ( $Files < 3 ) {
    push(@Altitudes,"  ACM Connectivity Failure!");
    $Errors{"ACMReadFail"}="ACM Config file Download Problem!  Only saw $Files Files.";
    $Errors{"ACMReadFail-01"}="  * Found at $Date";
    $Errors{"ACMReadFail-02"}="  * This COULD mean configuration options are corrupt or missing ( i.e. Software Keys ).";
  }
}

sub Process_ACM_File_Read {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) Console: - ACM: In DownLoad: listACMFiles: No. of Files in ACM is: (.*)/;

  my $Date=$1;
  my $Files=$2;

  if ( $Files == 0 ) {
    push(@Altitudes,"  ACM Config file read failed!");
    $Errors{"ACMRead"}="ACM Config file read failed!";
    $Errors{"ACMRead-01"}="  * Found at $Date";
    $Errors{"ACMRead-02"}="  * We were unable to read any files from the ACM.";
    $Errors{"ACMRead-03"}="  * Validate the ATG Configuration and Keys";
  }
}


sub Process_Key_Feature {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) Console: - SW_KEYS: AbsControlServiceImpl: displyKeyValuesLogger\(\): keyValues.getFeature\(\)          : (.*)/;
#2014-04-29 00:29:40,361 Console: - SW_KEYS: AbsControlServiceImpl: displyKeyValuesLogger(): keyValues.getFeature()          : 101

  my $Date=$1;
  my $Feature=$2;

  $KeyCurrent=$2;
}


sub Process_Key_Feature_Status {
  my $StateLine=$_[0];

  print "Key Status : \$KeysInstalled{$KeyCurrent} :$KeysInstalled{$KeyCurrent}:\n" if ( $Verbose );
  if ( ! $KeyCurrent ) {
    $Investigation{"Keys-$KeyCurrent"}="Found Undefined key value $KeyCurrent.  Please notify NetOps.";
  }

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) Console: - SW_KEYS: AbsControlServiceImpl: displyKeyValuesLogger\(\): keyValues.getKeyStatus\(\)        : (.*)/;

  my $Date=$1;
  my $Feature=$2;

  if ( $KeysInstalled{$KeyCurrent} ) {
    if ( $KeysInstalled{$KeyCurrent} ne $Feature ) {
      $KeysChanged{$KeyCurrent}="Key installation status of $KeysNamed{$KeyCurrent} changed on $Date";
    }
  }

  $KeysInstalled{"$KeyCurrent"}=$Feature;
}


sub Process_Key_Feature_Start {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) Console: - SW_KEYS: AbsControlServiceImpl: displyKeyValuesLogger\(\): keyValues.getStartDate\(\)        : (.*)/;

  my $Date=$1;
  my $Feature=$2;

  $KeysStart{"$KeyCurrent"}=$Feature;
}


sub Process_Key_Feature_End {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) Console: - SW_KEYS: AbsControlServiceImpl: displyKeyValuesLogger\(\): keyValues.getEndDate\(\)          : (.*)/;


  my $Date=$1;
  my $Feature=$2;

  $KeysEnd{"$KeyCurrent"}=$Feature;
}


sub Process_Device_Notify {
  # Waiting on descriptoing of the lines
  my $StateLine=$_[0];
  return unless ( $StateLine =~ /RESET/ );

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).* Notifying (.*)/;

  my $Date=$1;
  my $Message=$2;

  push(@Altitudes,"  Notifying $Message");
}


sub Process_Device_Discovered {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*AMP: The (.*): is discovered/;

  my $Date=$1;
  my $Device=$2;

  push(@Altitudes,"  Discovered $Device") if ( $opt_devices );
  push(@Devices, "$Date - $Device");
}


sub Process_QoS_Fail {
  my $StateLine=$_[0];
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*[Messages|Console]: ATG4K kernel: rule prio 0 protocol 800 reclassify is buggy packet dropped/;

  $Last_QoS_Fail=$1;
  $Last_QoS_Fail_Test=$Last_QoS_Fail;
  $Last_QoS_Fail_Test =~ s/:\d\d,.*//g;

  $QoS_Fails++;
}


sub Process_Last_Repeat {
  my $StateLine=$_[0];

  return if ( ! $Last_QoS_Fail );
  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*).*[Messages|Console]: ATG4K last message repeated (.*) times/;

  $Last_Repeat=$1;
  $Repeats=$2;
  $Last_Repeat_Test=$Last_Repeat;
  $Last_Repeat_Test =~ s/:\d\d,.*//g;

  if ( ( $Repeats > 200 ) && ( $Last_QoS_Fail_Test eq $Last_Repeat_Test ) ) {
    push(@Altitudes,"  QoS Failure streak : $Repeats at $Last_QoS_Fail");
    $Investigation{"$Last_QoS_Fail-QoS-Fails"}="QoS Failure streak : $Repeats at $Last_QoS_Fail";
  } else {
    $Last_QoS_Fail="";
    $Last_Repeat="";
  }
}


sub Process_DriftLine {
  my $StateLine=$_[0];

  $StateLine =~ /(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\,*\d*) Drift: (.*)/;
  $LastDrift=$2;
}


sub Process_Airlink {
  my $Line=$_[0];
  my $DRC; my $SINR;

  # The ATG Rebooted.  No DRC, etc.
  if ( $Line =~ /DRC_BUFFER,/ )  {
    $Line =~ /(.*) Airlink: Latitude (.*) : Longitude (.*) : Altitude (.*)/;
    $LastLat=$2;
    $LastLon=$3;
    $LastAlt=$4;
    $LastCell="Reboot";
    $LastSector="Reboot";
  } else {
    $Line =~ /(.*) Airlink: Latitude (.*) : Longitude (.*) : Altitude (.*), DRC_BUFFER (.*), BEST_ASP_SINR_BUFFER (.*) , PILOT_PN_ASP .*, Tx_AGC .*, Rx_AGC0 .*, Rx_AGC1 .*, Cell (\d+), Sector (\d+)/;
    $LastLat=$2;
    $LastLon=$3;
    $LastAlt=$4;
    $DRC=$5;
    $SINR=$6;
    $LastCell=$7;
    $LastSector=$8;
  }

  push(@TotalDRC, $DRC);
  push(@TotalSINR, $SINR);

  $Line.=", LastPacketLoss $LastPacketLoss, LastLatency $LastLatency";
  push(@AirlinkData, $Line);
}


sub Process_GGTT {
  my $Line=$_[0];
  my $GGTTLine;
 
  $Line =~ /(.*) GGTT: (.*) Call #-*\d+ (.*), GDID (.*), DeviceID (.*), Result (.*)/;
  my $TimeStamp=$1;
  my $Direction=$2;
  my $Change=$3;
  my $GDID=$4;
  my $DeviceID=$5;
  my $Result=$6;

  if ( $Change =~ /Started/ ) {
    $CallCount++;
    $GGTTLine="$TimeStamp GGTT: Direction $Direction, LastLat $LastLat, LastLon $LastLon, LastAlt $LastAlt, Started $CallCount, GDID $GDID, DeviceID $DeviceID, Result $Result";
  } elsif ( $Change =~ /Closed/ ) {
    $CallCount--;
    $GGTTLine="$TimeStamp GGTT: Direction $Direction, LastLat $LastLat, LastLon $LastLon, LastAlt $LastAlt, Closed $CallCount, GDID $GDID, DeviceID $DeviceID, Result $Result";
  } else {
    $GGTTLine="$TimeStamp GGTT: Direction $Direction, LastLat $LastLat, LastLon $LastLon, LastAlt $LastAlt, $Change $CallCount, GDID $GDID, DeviceID $DeviceID, Result $Result";
  }
  push(@GGTTData, $GGTTLine);
}


sub Process_GGTTSMS {
  my $Line=$_[0];
  my $GGTTLine;

  $Line =~ /(.*) GGTTSMS: (.*), Status (.*), GDID (.*), DeviceID (.*), Result (.*)/;
  my $TimeStamp=$1;
  my $Direction=$2;
  my $Status=$3;
  my $GDID=$4;
  my $DeviceID=$5;
  my $Result=$6;

  if ( $Direction =~ /Sent/ ) {
    $GGTTLine="$TimeStamp GGTTSMS: Direction $Direction, Status $Status, LastLat $LastLat, LastLon $LastLon, LastAlt $LastAlt, GDID $GDID, DeviceID $DeviceID, Result $Result";
  } elsif ( $Direction =~ /Closed/ ) {
    $GGTTLine="$TimeStamp GGTTSMS: Direction $Direction, Status $Status, LastLat $LastLat, LastLon $LastLon, LastAlt $LastAlt, GDID $GDID, DeviceID $DeviceID, Result $Result";
  } else {
    $GGTTLine="$TimeStamp GGTTSMS: Direction $Direction, Status $Status, LastLat $LastLat, LastLon $LastLon, LastAlt $LastAlt, GDID $GDID, DeviceID $DeviceID, Result $Result";
  }
  push(@GGTTSMSData, $GGTTLine);
}


sub Calculate_Signals {
  my $LoopCount;
  my $DRCV=0;
  my $SINRV;
  my $Tmp;

  $LoopCount=0;
  if ( $ATGVersion =~ /^2.[123456789]/ ) {
    foreach my $Loop ( @TotalDRC ) {
      next if ( ! $Loop );
      my @DRC=split(' ',$Loop);
      if ( $DRC[0] == "1" ) {
        $Tmp=$DRC[1] +16;
      } else {
        $Tmp=$DRC[1];
      }
      $DRCV += $DRCValues[$Tmp];
      $LoopCount++;
    }
    if ( $LoopCount == 0 ) {
      $TotalDRC="0.0";
    } else {
      $TotalDRC=sprintf("%.2f", ($DRCV/$LoopCount) );
    }
  } else {
    foreach my $Loop ( @TotalDRC ) {
      next if ( ! $Loop );
      my @DRC=split(' ',$Loop);
      $Tmp=$DRC[0];
      $DRCV += $DRCValues[$Tmp];
      $LoopCount++;
    }
    $TotalDRC=sprintf("%.2f", ($DRCV/$LoopCount) );
  }

  $LoopCount=0;
  foreach my $Loop ( @TotalSINR ) {
    next if ( ! $Loop );
    my @SINR=split(' ',$Loop);
    for my $S (@SINR) {
      $SINRV += $S;
      $LoopCount++;
    }
  }
#  $TotalSINR=($SINRV/$LoopCount);
  if ( $LoopCount == 0 ) {
    $TotalSINR="0.0";
  } else {
    $TotalSINR=sprintf("%.2f", ($SINRV/$LoopCount) );
  }
}


sub Get_DRC {
  my $Tmp=$_[0];
  my $Index;

  if ( $ATGVersion =~ /^2.[123456789]/ ) {
    my @DRC=split(' ',$Tmp);
    if ( $DRC[0] == "1" ) {
      $Index=$DRC[1] +16;
    } else {
      $Index=$DRC[1];
    }
  } else {
    my @DRC=split(' ',$Tmp);
    $Index=$DRC[0];
  }
  my $DRC=$DRCValues[$Index];

  return( $DRC ); 
}


sub RickRoll {
  print "\n";
  print "\n";
  print "** And now for something completely different\n";
  print "\n";
  print "We're no strangers to love\n";
  print "You know the rules and so do I\n";
  print "A full commitment's what I'm thinking of\n";
  print "You wouldn't get this from any other guy\n";
  print "\n";
  print "I just wanna tell you how I'm feeling\n";
  print "Gotta make you understand\n";
  &RRRefrain;
  print "We've known each other for so long\n";
  print "Inside, we both know what's been going on\n";
  print "We know the game and we're gonna play it\n";
  print "\n";
  print "And if you ask me how I'm feeling\n";
  print "Don't tell me you're too blind to see\n";
  &RRRefrain;
  &RRRefrain;
  print "(Ooh, give you up)\n";
  print "(Ooh, give you up)\n";
  print "Never gonna give, never gonna give\n";
  print "(Give you up)\n";
  print "Never gonna give, never gonna give\n";
  print "(Give you up)\n";
  print "\n";
  print "We've known each other for so long\n";
  print "Your heart's been aching, but you're too shy to say it\n";
  print "Inside, we both know what's been going on\n";
  print "We know the game and we're gonna play it\n";
  print "\n";
  print "I just wanna tell you how I'm feeling\n";
  print "Gotta make you understand\n";
  &RRRefrain;
  &RRRefrain;
}

sub RRRefrain {
print "\n";
print "Never gonna give you up\n";
print "Never gonna let you down\n";
print "Never gonna run around and desert you\n";
print "Never gonna make you cry\n";
print "Never gonna say goodbye\n";
print "Never gonna tell a lie and hurt you\n";
print "\n";
}


sub Get_GGTT {
  my $TransFilesDir="/opt/log/Accuroam/";
  my $FileBase=$TransFilesDir."trans.log.*";
  my @ProcessMe;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID;

  $PopulateCallCount=0;

  $DateStart =~ /(\d\d\d\d\/\d\d\/\d\d)_/;
  my $Start=$1;
  $Start =~ s,/,,g;
  print "Start : $DateStart : $Start\n" if ( $Verbose );
  $DateEnd =~ /(\d\d\d\d\/\d\d\/\d\d)_/;
  my $End=$1;
  $End =~ s,/,,g;
  print "Finish : $DateEnd : $End\n" if ( $Verbose );
  open(INPUT, "ls -1rt $FileBase |");
  while(<INPUT>) {
    chomp;
    my $Line=$_;
    $Line =~ /.log.(\d\d\d\d\d\d\d\d)/;
    my $Current=$1;
    if (( $Start <= $Current ) && ( $Current <= $End )) {
      push(@ProcessMe, $Line);
    }
  }
  close(INPUT);
  @ProcessMe=sort(@ProcessMe);
  foreach my $Loop (@ProcessMe) {
    print "Processing $Loop: ACID :$ACID:\n" if ( $Verbose );
    open(INPUT, "/bin/grep $ACID $Loop |");
    while(<INPUT>) {
      chomp;
      my $Line = $_;
      $csv->parse( $Line );
      my @Line=$csv->fields( );
      my $Type=$Line[5];
      # Text Messages
      &Process_SipMessage(@Line) if ( $Type eq "SipMessage" );
      &Process_MapMtShortMessage(@Line) if ( $Type eq "MapMtShortMessage" );
      # SipCalls/xxx
      &Process_MOSipCall(@Line) if ( $Type eq "SipCall" );
      &Process_MOSipCallEnded(@Line) if ( $Type eq "SipCallEnded" );
      &Process_MTSipCall(@Line) if ( $Type eq "SipMtCall" );
      &Process_MTSipCallEnded(@Line) if ( $Type eq "SipMtCallEnded" );
    }
  }
}


sub Process_SipMessage {
  my (@Line)=@_;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID; my $Result;

  my $DateTime=$Line[2];
  $DateTime =~ /(\d\d):(\d\d):(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/;

  #my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, undef, $Callee, $Content, undef, undef, $ID, undef, undef, undef, undef, undef, $Result) = $csv->fields();

  $Day=$1;
  $Mon=$2;
  $Year=$3;
  $Hour=$4;
  $Min=$5;
  $Sec=$6;
  $Mili="000000";

  $SIPStatus=$Line[8];
  $SIPStatus="Sent" if ( $SIPStatus eq "0200" );
  $GDID=$Line[9];
  $DeviceID=$Line[15];
  $DeviceID =~ s/.*msisdn><uagent>//;
  $DeviceID =~ s,</uagent>.*,,;
  $Result=$Line[28];

  $TimeStamp=$Year."-".$Mon."-".$Day." ".$Hour.":".$Min.":".$Sec.",".$Mili;

  if ( $SIPStatus eq "Sent") {
    $PopulateCallCount++;
    print "  $TimeStamp - Sent a SMS Message GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  } else {
    print "  $TimeStamp - SMS Message error $SIPStatus in $Loop. GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  }
  push(@CallData, "$TimeStamp GGTTSMS: SipMessage, Status $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
  push(@LogLines, "$TimeStamp GGTTSMS: SipMessage, Status $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
}


sub Process_MapMtShortMessage {
  my (@Line)=@_;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID; my $Result;

  my $DateTime=$Line[2];
  $DateTime =~ /(\d\d):(\d\d):(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/;

#foreach my $Loop (0..$#Line) {
#  print "\$Line[$Loop] :$Line[$Loop]:\n";
#}

#  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, $Length, $Content, undef, undef, undef, $ID, undef, undef, $Result) = $csv->fields();

  $Day=$1;
  $Mon=$2;
  $Year=$3;
  $Hour=$4;
  $Min=$5;
  $Sec=$6;
  $Mili="000000";

  $SIPStatus=$Line[8];
  $SIPStatus="Received" if ( $SIPStatus eq "0000" );
  $GDID=$Line[20];
  $DeviceID=$Line[16];
  $DeviceID =~ s/.*msisdn><uagent>//;
  $DeviceID =~ s,</uagent>.*,,;
  $Result=$Line[22];

  $TimeStamp=$Year."-".$Mon."-".$Day." ".$Hour.":".$Min.":".$Sec.",".$Mili;

  if ( $SIPStatus eq "Sent") {
    $PopulateCallCount++;
    print "  $TimeStamp - Sent a SMS Message GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  } else {
    print "  $TimeStamp - SMS Message error $SIPStatus in $Loop. GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  }
  push(@CallData, "$TimeStamp GGTTSMS: SipMtMessage, Status $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
  push(@LogLines, "$TimeStamp GGTTSMS: SipMtMessage, Status $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
}


sub Process_MOSipCall {
  my (@Line)=@_;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID; my $Result;

  my $DateTime=$Line[2];
  $DateTime =~ /(\d\d):(\d\d):(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/;

  $Day=$1;
  $Mon=$2;
  $Year=$3;
  $Hour=$4;
  $Min=$5;
  $Sec=$6;
  $Mili="000000";

  $SIPStatus=$Line[8];
  $SIPStatus="Started" if ( $SIPStatus eq "0200" );
  $GDID=$Line[9];
  $DeviceID=$Line[19];
  $DeviceID =~ s/.*msisdn><uagent>//;
  $DeviceID =~ s,</uagent>.*,,;
  $Result=$Line[29];

  $TimeStamp=$Year."-".$Mon."-".$Day." ".$Hour.":".$Min.":".$Sec.",".$Mili;

  if ( $SIPStatus eq "Started") {
    $PopulateCallCount++;
    print "  $TimeStamp - Added a call in $Loop. CallCount :$PopulateCallCount: GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  } else {
    print "  $TimeStamp - Call error $SIPStatus in $Loop. CallCount :$PopulateCallCount: GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  }
  push(@CallData, "$TimeStamp GGTT: Mobile Orig Call $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
  push(@LogLines, "$TimeStamp GGTT: Mobile Orig Call #$PopulateCallCount $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
}


sub Process_MOSipCallEnded {
  my (@Line)=@_;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID; my $Result;

  my $DateTime=$Line[2];
  $DateTime =~ /(\d\d):(\d\d):(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/;

  $Day=$1;
  $Mon=$2;
  $Year=$3;
  $Hour=$4;
  $Min=$5;
  $Sec=$6;
  $Mili="000000";

  $GDID=$Line[9];
  $DeviceID=$Line[19];
  $DeviceID =~ s/.*msisdn><uagent>//;
  $DeviceID =~ s,</uagent>.*,,;
  $Result=$Line[27];

  $SIPStatus=$Line[8];
  $SIPStatus="Closed" if ( $SIPStatus eq "0000" );
  
  # Throw away, captured in SipCall
  return if ( $Result eq "CallNotConnected");

  $TimeStamp=$Year."-".$Mon."-".$Day." ".$Hour.":".$Min.":".$Sec.",".$Mili;
  print "  $TimeStamp - Closed a call in $Loop CallCount :$PopulateCallCount: GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
  print "    $Line\n" if ( $Verbose );
  push(@CallData, "$TimeStamp GGTT: Mobile Orig Call Closed, GDID $GDID, DeviceID $DeviceID, Result $Result");
  push(@LogLines, "$TimeStamp GGTT: Mobile Orig Call #$PopulateCallCount $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
  $PopulateCallCount--;
  # It's possible due to timezones and logs a call End was listed before a beginning.  Nullify that.
  $PopulateCallCount=0 if ( $PopulateCallCount < 0 );
}


sub Process_MTSipCall {
  my (@Line)=@_;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID; my $Result;

  my $DateTime=$Line[2];
  $DateTime =~ /(\d\d):(\d\d):(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/;

  $Day=$1;
  $Mon=$2;
  $Year=$3;
  $Hour=$4;
  $Min=$5;
  $Sec=$6;
  $Mili="000000";

  $SIPStatus=$Line[8];
  $SIPStatus="Started" if ( $SIPStatus eq "0200" );
  $GDID=$Line[9];
  $DeviceID=$Line[22];
  $DeviceID =~ s/.*msisdn><uagent>//;
  $DeviceID =~ s,</uagent>.*,,;
  $Result=$Line[29];

  $TimeStamp=$Year."-".$Mon."-".$Day." ".$Hour.":".$Min.":".$Sec.",".$Mili;

  if ( $SIPStatus eq "Started") {
    $PopulateCallCount++;
    print "  $TimeStamp - Added a call in $Loop. CallCount :$PopulateCallCount: GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  } else {
    print "  $TimeStamp - Call error $SIPStatus in $Loop. CallCount :$PopulateCallCount: GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
    print "    $Line\n" if ( $Verbose );
  }
  push(@CallData, "$TimeStamp GGTT: Mobile Term Call $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
  push(@LogLines, "$TimeStamp GGTT: Mobile Term Call #$PopulateCallCount $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
}


sub Process_MTSipCallEnded {
  my (@Line)=@_;
  my $Day; my $Mon; my $Year; my $Hour; my $Min; my $Sec; my $Mili; my $TimeStamp;
  my $GDID; my $SIPStatus; my $DeviceID; my $Result;

  my $DateTime=$Line[2];
  $DateTime =~ /(\d\d):(\d\d):(\d\d\d\d)-(\d\d):(\d\d):(\d\d)/;

  $Day=$1;
  $Mon=$2;
  $Year=$3;
  $Hour=$4;
  $Min=$5;
  $Sec=$6;
  $Mili="000000";

  $GDID=$Line[9];
  $DeviceID=$Line[22];
  $DeviceID =~ s/.*msisdn><uagent>//;
  $DeviceID =~ s,</uagent>.*,,;
  $Result=$Line[27];

  $SIPStatus=$Line[8];
  $SIPStatus="Closed" if ( $SIPStatus eq "0000" );
  
  # Throw away, captured in SipCall
  return if ( $Result eq "CallNotConnected");

  $TimeStamp=$Year."-".$Mon."-".$Day." ".$Hour.":".$Min.":".$Sec.",".$Mili;
  print "  $TimeStamp - Closed a call in $Loop CallCount :$PopulateCallCount: GDID :$GDID: DeviceID :$DeviceID: Result :$Result:\n" if ( $Verbose );
  print "    $Line\n" if ( $Verbose );
  push(@CallData, "$TimeStamp GGTT: Mobile Term Call Closed, GDID $GDID, DeviceID $DeviceID, Result $Result");
  push(@LogLines, "$TimeStamp GGTT: Mobile Term Call #$PopulateCallCount $SIPStatus, GDID $GDID, DeviceID $DeviceID, Result $Result");
  $PopulateCallCount--;
  # It's possible due to timezones and logs a call End was listed before a beginning.  Nullify that.
  $PopulateCallCount=0 if ( $PopulateCallCount < 0 );
}


sub Create_KML {

  my $Date=$Start."-".$End;
  my $TmpFile="/var/www/html/KML/InfOps_".$Tail."-".$DateRange.".kml";
  my $TargetFile="/var/www/html/KML/InfOps_".$Tail."-".$DateRange.".kmz";
  my $TargetFileURL="http://10.241.1.132/KML/InfOps_".$Tail."-".$DateRange.".kmz";
  my $Time; my $Lat; my $Lon; my $Alt; my $DRC; my $SINR; my $Cell; my $Sector;
  my $PPN; my $TxA; my $RxA0; my $RxA1;
  my $LabelScale;
  my $Type;
  
  # Define Icon Styles
  my $IconScale=0.8;
  my $IconScaleMedium=0.9;
  my $IconScaleLarge=1.0;
  $LabelScale=1.0;

  print "Creating KML file $TargetFileURL\n";
  open(OUTPUT, ">$TmpFile") or die "Can't open $TmpFile :$?: :$!:\n";

  # Print Header Info
  print OUTPUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  print OUTPUT "<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n";
  
  # Start the Doc
  print OUTPUT "<Document>\n";
  print OUTPUT "  <name>Flight of $Tail on $DateStart</name>\n";
  print OUTPUT "  <open>1</open>\n";
  print OUTPUT "  <LookAt id=\"\">\n";
  print OUTPUT "    <altitude>1</altitude>\n";
  print OUTPUT "    <heading>0</heading>\n";
  print OUTPUT "    <latitude>38</latitude>\n";
  print OUTPUT "    <longitude>-98</longitude>\n";
  print OUTPUT "    <range>4000000</range>\n";
  print OUTPUT "    <tilt>3</tilt>\n";
  print OUTPUT "  </LookAt>\n";
  print OUTPUT "  <ScreenOverlay id=\"\">\n";
  print OUTPUT "    <Icon id=\"content\">\n";
  print OUTPUT "      <href>http://10.241.1.70/media/legends/drc-lgd.png</href>\n";
  print OUTPUT "    </Icon>\n";
  print OUTPUT "    <description>drc Legend</description>\n";
  print OUTPUT "    <name>Legend</name>\n";
  print OUTPUT "    <overlayXY x=\"0\" xunits=\"fraction\" y=\"1\" yunits=\"fraction\" />\n";
  print OUTPUT "    <rotationXY></rotationXY>\n";
  print OUTPUT "    <screenXY x=\"0\" xunits=\"fraction\" y=\"1\" yunits=\"fraction\" />\n";
  print OUTPUT "  </ScreenOverlay>\n";
  # Moving this earlier to put on top of the Green Circles 
  # IF GGTT selected 
  if ( $GGTT_Enable ) {
    # GGTT Call Data
    print OUTPUT "  <Folder>\n";
    print OUTPUT "    <name>GGTT Call Data</name>\n";
    # Define the Styles ( which go in the MAPS ) for GGTT
    # Call Error
    # Red
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Error-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>https://maps.google.com/mapfiles/kml/shapes/earthquake.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Error-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>https://maps.google.com/mapfiles/kml/shapes/earthquake.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Call Started
    # Red
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Red-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
#    print OUTPUT "          <href>http://maps.google.com/mapfiles/kml/shapes/phone.png</href>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Red-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Green
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Green-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Green-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Call Ended
    # Red
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Hangup-Red-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
#    print OUTPUT "          <href>http://maps.google.com/mapfiles/kml/shapes/phone-hangup.png</href>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone-hangup.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Hangup-Red-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone-hangup.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Green
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Hangup-Green-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone-hangup.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTT-Hangup-Green-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/phone-hangup.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Define Maps for the Colors
    # GGTT CAll
    # Error
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTT-Error-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Error-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Error-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Red
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTT-Red-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Red-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Red-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Green
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTT-Green-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Green-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Green-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # GGTT Hangup
    # Red
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTT-Hangup-Red-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Hangup-Red-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Hangup-Red-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Green
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTT-Hangup-Green-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Hangup-Green-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTT-Hangup-Green-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    foreach my $Loop ( @GGTTData ) {
      $Loop =~ /(.*) GGTT: Direction (.*), LastLat (.*), LastLon (.*), LastAlt (.*), (.*) (\d+), GDID (.*), DeviceID (.*), Result (.*)/;
      my $Time=$1;
      my $Direction=$2;
      my $Lat=$3;
      my $Lon=$4;
      my $Alt=$5;
        $Alt=$Alt+100;
      my $State=$6;
      my $Count=$7;
      my $GDID=$8;
      my $DeviceID=$9;
      my $Result=$10;
      my $GGTTColor;
      print OUTPUT "    <Placemark>\n";
      my ( undef, $TS )=split(' ', $Time); 
      my ( $TSShort, undef )=split(',', $TS);
      if ( $Count < 3 ) {
        $GGTTColor="Green";
      } else {
        $GGTTColor="Red";
      }
      if ( $State eq "Started" ) {
        $Type="GGTT" 
      } elsif ( $State eq "Closed" ) {
        $Type="GGTT-Hangup"
      } else {
        $Type="GGTT-Error"
      }
      if ( $Type eq "GGTT-Error" ) {
        print OUTPUT "      <styleUrl>#BA-Style-".$Type."-Map</styleUrl>\n";
      } else {
        print OUTPUT "      <styleUrl>#BA-Style-".$Type."-".$GGTTColor."-Map</styleUrl>\n";
      }
      print OUTPUT "      <name>Call $State at $TSShort CT </name>\n";
      print OUTPUT "  <LookAt id=\"\">\n";
      print OUTPUT "    <altitude>1</altitude>\n";
      print OUTPUT "    <heading>0</heading>\n";
      print OUTPUT "    <latitude>$Lat</latitude>\n";
      print OUTPUT "    <longitude>$Lon</longitude>\n";
      print OUTPUT "    <range>400000</range>\n";
      print OUTPUT "    <tilt>3</tilt>\n";
      print OUTPUT "  </LookAt>\n";
      my $TSMark=$Time;
      $TSMark =~ s/ /T/g;
      $TSMark =~ s/,\d+//;
      $TSMark =~ s/$/Z/g;
      print OUTPUT "      <TimeStamp><when>$TSMark></when></TimeStamp>\n";
      print OUTPUT "      <ExtendedData>\n";
      print OUTPUT "        <Data name=\"Time\">\n";
      print OUTPUT "          <value>$Time CT </value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Direction\">\n";
      print OUTPUT "          <value>$Direction</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Result\">\n";
      print OUTPUT "          <value>$Result</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"GDID\">\n";
      print OUTPUT "          <value>$GDID</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"DeviceID\">\n";
      print OUTPUT "          <value>$DeviceID</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Call Count\">\n";
      print OUTPUT "          <value>$Count</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Lat\">\n";
      print OUTPUT "          <value>$Lat</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Lon\">\n";
      print OUTPUT "          <value>$Lon</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Alt\">\n";
      print OUTPUT "          <value>$Alt</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "      </ExtendedData>\n";
      print OUTPUT "      <Point>\n";
      print OUTPUT "        <altitudeMode>absolute</altitudeMode>\n";
      print OUTPUT "        <coordinates>$Lon,$Lat,$Alt</coordinates>\n";
      print OUTPUT "      </Point>\n";
      print OUTPUT "    </Placemark>\n";
    }
    print OUTPUT "  </Folder>\n";
    # GGTT SMS Data
    print OUTPUT "  <Folder>\n";
    print OUTPUT "    <name>GGTT SMS Data</name>\n";
    # Define the Styles ( which go in the MAPS ) for GGTT
    # Call Error
    # Red
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMessage-Error-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>https://maps.google.com/mapfiles/kml/shapes/earthquake.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMessage-Error-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>https://maps.google.com/mapfiles/kml/shapes/earthquake.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Call Started
    # Red
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMessage-Red-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
#    print OUTPUT "          <href>http://maps.google.com/mapfiles/kml/shapes/phone.png</href>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMessage-Red-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Green
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMessage-Green-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMessage-Green-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Call Ended
    # Error
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMt-Error-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office-90.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMt-Error-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office-90.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Red
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMt-Red-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office-90.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMt-Red-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF0000FF</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office-90.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScaleLarge</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Green
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMt-Green-Visible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office-90.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>$LabelScale</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    #
    print OUTPUT "    <Style id=\"BA-Style-GGTTSMS-SipMt-Green-InVisible\">\n";
    print OUTPUT "      <IconStyle>\n";
    print OUTPUT "        <color>FF00FF00</color>\n";
    print OUTPUT "        <Icon>\n";
    print OUTPUT "          <href>http://10.241.1.132/Icons/post_office-90.png</href>\n";
    print OUTPUT "        </Icon>\n";
    print OUTPUT "        <scale>$IconScale</scale>\n";
    print OUTPUT "      </IconStyle>\n";
    print OUTPUT "      <LabelStyle>\n";
    print OUTPUT "        <scale>0</scale>\n";
    print OUTPUT "      </LabelStyle>\n";
    print OUTPUT "      <BalloonStyle>\n";
    print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
    print OUTPUT "      </BalloonStyle>\n";
    print OUTPUT "    </Style>\n";
    # Define Maps for the Colors
    # GGTTSMS SipMessage
    # Error
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTTSMS-SipMessage-Error-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMessage-Error-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMessage-Error-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Red
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTTSMS-SipMessage-Red-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMessage-Red-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMessage-Red-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Green
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTTSMS-SipMessage-Green-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMessage-Green-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMessage-Green-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # GGTT SipMT
    # Error
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTTSMS-SipMt-Error-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMt-Error-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMt-Error-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Red
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTTSMS-SipMt-Red-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMt-Red-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMt-Red-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    # Green
    print OUTPUT "    <StyleMap id=\"BA-Style-GGTTSMS-SipMt-Green-Map\">\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>highlight</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMt-Green-Visible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "      <Pair>\n";
    print OUTPUT "        <key>normal</key>\n";
    print OUTPUT "        <styleUrl>#BA-Style-GGTTSMS-SipMt-Green-InVisible</styleUrl>\n";
    print OUTPUT "      </Pair>\n";
    print OUTPUT "    </StyleMap>\n";
    foreach my $Loop ( @GGTTSMSData ) {
      $Loop =~ /(.*) GGTTSMS: Direction (.*), Status (.*) LastLat (.*), LastLon (.*), LastAlt (.*), GDID (.*), DeviceID (.*), Result (.*)/;
      my $Time=$1;
      my $Direction=$2;
      my $Status=$3;
      my $Lat=$4;
      my $Lon=$5;
      my $Alt=$6;
      my $GDID=$7;
      my $DeviceID=$8;
      my $Result=$9;
      my $GGTTColor;
        $Alt=$Alt+100;
      print OUTPUT "    <Placemark>\n";
      my ( undef, $TS )=split(' ', $Time); 
      my ( $TSShort, undef )=split(',', $TS);
      if ( $Result eq "Success" ) {
        $GGTTColor="Green";
      } else {
        $GGTTColor="Red";
      }
      if ( $Direction eq "SipMessage" ) {
        $Type="GGTTSMS-SipMessage";
      } elsif ( $Direction eq "SipMtMessage" ) {
        $Type="GGTTSMS-SipMt";
      } else {
        $Type="GGTTSMS-Error";
      }
      my $EngDirection;
      if ( $Direction eq "SipMessage" ) {
        $EngDirection="Mobile Orig";
      } elsif ( $Direction eq "SipMtMessage" ) {
        $EngDirection="Mobile Term";
      } else {
        $EngDirection="Unknonw, tell Robert";
      }
      print OUTPUT "      <styleUrl>#BA-Style-".$Type."-".$GGTTColor."-Map</styleUrl>\n";
      print OUTPUT "      <name>SMS $EngDirection at $TSShort CT </name>\n";
      print OUTPUT "  <LookAt id=\"\">\n";
      print OUTPUT "    <altitude>1</altitude>\n";
      print OUTPUT "    <heading>0</heading>\n";
      print OUTPUT "    <latitude>$Lat</latitude>\n";
      print OUTPUT "    <longitude>$Lon</longitude>\n";
      print OUTPUT "    <range>400000</range>\n";
      print OUTPUT "    <tilt>3</tilt>\n";
      print OUTPUT "  </LookAt>\n";
      my $TSMark=$Time;
      $TSMark =~ s/ /T/g;
      $TSMark =~ s/,\d+//;
      $TSMark =~ s/$/Z/g;
      print OUTPUT "      <TimeStamp><when>$TSMark></when></TimeStamp>\n";
      print OUTPUT "      <ExtendedData>\n";
      print OUTPUT "        <Data name=\"Time\">\n";
      print OUTPUT "          <value>$Time CT </value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"EngDirection\">\n";
      print OUTPUT "          <value>$EngDirection</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Status\">\n";
      print OUTPUT "          <value>$Status</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Result\">\n";
      print OUTPUT "          <value>$Result</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"GDID\">\n";
      print OUTPUT "          <value>$GDID</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"DeviceID\">\n";
      print OUTPUT "          <value>$DeviceID</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Lat\">\n";
      print OUTPUT "          <value>$Lat</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Lon\">\n";
      print OUTPUT "          <value>$Lon</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "        <Data name=\"Alt\">\n";
      print OUTPUT "          <value>$Alt</value>\n";
      print OUTPUT "        </Data>\n";
      print OUTPUT "      </ExtendedData>\n";
      print OUTPUT "      <Point>\n";
      print OUTPUT "        <altitudeMode>absolute</altitudeMode>\n";
      print OUTPUT "        <coordinates>$Lon,$Lat,$Alt</coordinates>\n";
      print OUTPUT "      </Point>\n";
      print OUTPUT "    </Placemark>\n";
    }
    print OUTPUT "  </Folder>\n";

  }


  # Airlink Data Points
  print OUTPUT "  <Folder>\n";
  # Define the Styles ( which go in the MAPS ) for Airlink Data
  # UNKNOWN
  print OUTPUT "  <Style id=\"BA-Style-Unknown-Visible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>00000000</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScaleLarge</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>$LabelScale</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  #
  print OUTPUT "  <Style id=\"BA-Style-Unknown-InVisible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>00000000</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScaleLarge</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>0</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  # Red
  print OUTPUT "  <Style id=\"BA-Style-Red-Visible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF0000FF</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScaleLarge</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>$LabelScale</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  #
  print OUTPUT "  <Style id=\"BA-Style-Red-InVisible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF0000FF</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScaleMedium</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>0</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  # Orange
  print OUTPUT "  <Style id=\"BA-Style-Orange-Visible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF1772F8</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScaleMedium</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>$LabelScale</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  #
  print OUTPUT "  <Style id=\"BA-Style-Orange-InVisible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF1772F8</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScaleMedium</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>0</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  # Yellow
  print OUTPUT "  <Style id=\"BA-Style-Yellow-Visible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF00FFFF</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScale</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>$LabelScale</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  #
  print OUTPUT "  </Style>\n";
  print OUTPUT "  <Style id=\"BA-Style-Yellow-InVisible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF00FFFF</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScale</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>0</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  # Olive
  print OUTPUT "  <Style id=\"BA-Style-Olive-Visible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF00CC99</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScale</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>$LabelScale</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  #
  print OUTPUT "  </Style>\n";
  print OUTPUT "  <Style id=\"BA-Style-Olive-InVisible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF00CC99</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScale</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>0</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  # Green
  print OUTPUT "  <Style id=\"BA-Style-Green-Visible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF00FF00</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScale</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>$LabelScale</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  #
  print OUTPUT "  <Style id=\"BA-Style-Green-InVisible\">\n";
  print OUTPUT "    <IconStyle>\n";
  print OUTPUT "      <color>FF00FF00</color>\n";
  print OUTPUT "      <Icon>\n";
  print OUTPUT "        <href>https://www.earthpoint.us/Dots/GoogleEarth/shapes/donut.png</href>\n";
  print OUTPUT "      </Icon>\n";
  print OUTPUT "      <scale>$IconScale</scale>\n";
  print OUTPUT "    </IconStyle>\n";
  print OUTPUT "    <LabelStyle>\n";
  print OUTPUT "      <scale>0</scale>\n";
  print OUTPUT "    </LabelStyle>\n";
  print OUTPUT "    <BalloonStyle>\n";
  print OUTPUT "      <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "    </BalloonStyle>\n";
  print OUTPUT "  </Style>\n";
  # Define Maps for the Colors
  # Unknown
  print OUTPUT "  <StyleMap id=\"BA-Style-Unknown-Map\">\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>highlight</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Unknown-Visible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>normal</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Unknown-InVisible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "  </StyleMap>\n";
  # Red
  print OUTPUT "  <StyleMap id=\"BA-Style-Red-Map\">\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>highlight</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Red-Visible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>normal</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Red-InVisible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "  </StyleMap>\n";
  # Orange
  print OUTPUT "  <StyleMap id=\"BA-Style-Orange-Map\">\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>highlight</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Orange-Visible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>normal</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Orange-InVisible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "  </StyleMap>\n";
  # Yellow
  print OUTPUT "  <StyleMap id=\"BA-Style-Yellow-Map\">\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>highlight</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Yellow-Visible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>normal</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Yellow-InVisible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "  </StyleMap>\n";
  # Olive
  print OUTPUT "  <StyleMap id=\"BA-Style-Olive-Map\">\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>highlight</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Olive-Visible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "    <Pair>\n";
  print OUTPUT "      <key>normal</key>\n";
  print OUTPUT "      <styleUrl>#BA-Style-Olive-InVisible</styleUrl>\n";
  print OUTPUT "    </Pair>\n";
  print OUTPUT "  </StyleMap>\n";
  # Green
  print OUTPUT "  <StyleMap id=\"BA-Style-Green-Map\">\n";
  print OUTPUT "  <Pair>\n";
  print OUTPUT "    <key>highlight</key>\n";
  print OUTPUT "    <styleUrl>#BA-Style-Green-Visible</styleUrl>\n";
  print OUTPUT "  </Pair>\n";
  print OUTPUT "  <Pair>\n";
  print OUTPUT "    <key>normal</key>\n";
  print OUTPUT "    <styleUrl>#BA-Style-Green-InVisible</styleUrl>\n";
  print OUTPUT "  </Pair>\n";
  print OUTPUT "</StyleMap>\n";
#rlh  print OUTPUT "  <Folder>\n";
  print OUTPUT "    <name>Datapoints</name>\n";

  foreach my $Loop ( @AirlinkData ) {
#print "\$Loop :$Loop:\n";
    my @SINR;
    my $SINRV;
    my $ASINR;
    my @DRC;
    my $DRCV;
    my $ADRC;
#    my $Aircraft;
    my $AircraftColor="Unknown";
#print "\$Loop :$Loop:\n";
    if ( $Loop =~ /Airlink: Lat/ ) {
      # ATG Rebooted.  Compensate
      if ( $Loop =~ /DRC_BUFFER,/ ) {
        $Loop =~ /(.*) Airlink: Latitude (.*) : Longitude (.*) : Altitude (.*)/;

        $Time=$1;
        $Lat=$2;
        $Lon=$3;
        $Alt=$4;
        $DRC="Rebooted";
        $SINR="Rebooted";
        $PPN="Rebooted";
        $TxA="Rebooted";
        $RxA0="Rebooted";
        $RxA1="Rebooted";
        $Cell="Rebooted";
        $Sector="Rebooted";
        $LastPacketLoss="Rebooted";
        $LastLatency="Rebooted";
        $ADRC="Rebooted";
        $ASINR="Rebooted";
        $AircraftColor="Red";
      } else {
        $Loop =~ /(.*) Airlink: Latitude (.*) : Longitude (.*) : Altitude (.*), DRC_BUFFER (.*), BEST_ASP_SINR_BUFFER (.*) , PILOT_PN_ASP (.*), Tx_AGC (.*), Rx_AGC0 (.*), Rx_AGC1 (.*), Cell (\d+), Sector (\d+), LastPacketLoss (.*), LastLatency (.*)/;

        $Time=$1;
        $Lat=$2;
        $Lon=$3;
        $Alt=$4;
        $DRC=$5;
        $SINR=$6;
        $PPN=$7;
        $TxA=$8;
        $RxA0=$9;
        $RxA1=$10;
        $Cell=$11;
        $Sector=$12;
        $LastPacketLoss=$13;
        $LastLatency=$14;
        # Calculate the Average DRC for the update
        @DRC=split(' ',$DRC);
        $ADRC=sprintf("%.2f", &Get_DRC( $DRC ));
        # What color should our bubbles be?
        if ( $ADRC < 307.2 ) {
          $AircraftColor="Red";
        } elsif ( ( $ADRC >= 307.2 ) &&  ( $ADRC < 614.4 ) ) {
          $AircraftColor="Orange";
        } elsif ( ( $ADRC >= 614.4 ) &&  ( $ADRC < 1228 ) ) {
          $AircraftColor="Yellow";
        } elsif ( ( $ADRC >= 1228.4 ) &&  ( $ADRC < 2456 ) ) {
          $AircraftColor="Olive";
        } elsif ( $ADRC >= 2456 ) {
          $AircraftColor="Green";
        } else {
          $AircraftColor="Unknown";
        }

        # Calculate the Average SINR for the update
        @SINR=split(' ',$SINR);
        for my $S (@SINR) {
          $SINRV += $S;
        }
        if ( $#SINR < 1 ) {
          $ASINR=0;
        } else {
          $ASINR=sprintf("%.2f",($SINRV/($#SINR +1)));
        }
      }
    } else {
      $Loop =~ /(\d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d,\d+) Airlink: .*Aircard Latitude (.*) : Longitude (.*) : Altitude (.*), DRC_BUFFER (.*), BEST_ASP_SINR_BUFFER (.*), PILOT_PN_ASP (.*), Tx_AGC (.*), Rx_AGC0 (.*), Rx_AGC1 (.*), Cell (\d+), Sector (\d+), LastPacketLoss (.*), LastLatency (.*)/;
      $Time=$1;
      $Lat=$2;
      $Lon=$3;
      $Alt=$4;
      $DRC=$5;
      $SINR=$6;
      $PPN=$7;
      $TxA=$8;
      $RxA0=$9;
      $RxA1=$10;
      $Cell=$11;
      $Sector=$12;
      $LastPacketLoss=$13;
      $LastLatency=$14;
    }

    print OUTPUT "    <Placemark>\n";
    my ( $FlightDate, $TS )=split(' ', $Time); 
    my ( $TSShort, undef )=split(',', $TS);
    $FlightDate =~ m,(\d+)-(\d+)-(\d+),;
    my $FlightDate2=$1.$2.$3;
 
    print OUTPUT "      <styleUrl>#BA-Style-".$AircraftColor."-Map</styleUrl>\n";
    print OUTPUT "      <name>$TSShort UTC </name>\n";
    print OUTPUT "  <LookAt id=\"\">\n";
    print OUTPUT "    <altitude>1</altitude>\n";
    print OUTPUT "    <heading>0</heading>\n";
    print OUTPUT "    <latitude>$Lat</latitude>\n";
    print OUTPUT "    <longitude>$Lon</longitude>\n";
    print OUTPUT "    <range>400000</range>\n";
    print OUTPUT "    <tilt>3</tilt>\n";
    print OUTPUT "  </LookAt>\n";
    my $TSMark=$Time;
    $TSMark =~ s/ /T/g;
    $TSMark =~ s/,\d+//;
    $TSMark =~ s/$/Z/g;
    print OUTPUT "      <TimeStamp><when>$TSMark></when></TimeStamp>\n";
    print OUTPUT "      <ExtendedData>\n";
    print OUTPUT "        <Data name=\"Time\">\n";
    print OUTPUT "          <value>$Time UTC </value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Last ATG Time Drift\">\n";
    print OUTPUT "          <value>$LastDrift</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Lat\">\n";
    print OUTPUT "          <value>$Lat</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Lon\">\n";
    print OUTPUT "          <value>$Lon</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Alt\">\n";
    print OUTPUT "          <value>$Alt</value>\n";
    print OUTPUT "        </Data>\n";
#    print OUTPUT "        <Data name=\"Last Packet Loss\">\n";
#    print OUTPUT "          <value>$LastPacketLoss</value>\n";
#    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Last Latency\">\n";
    print OUTPUT "          <value>$LastLatency</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Avg DRC This Ping\">\n";
    print OUTPUT "          <value>$ADRC ( Flight: $TotalDRC )</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Raw DRC Reported\">\n";
    print OUTPUT "          <value>$DRC</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Avg SINR This Ping\">\n";
    print OUTPUT "          <value>$ASINR ( Flight $TotalSINR )</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Raw SINR Reported\">\n";
    print OUTPUT "          <value>$SINR</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"PILOT_PN_AS_ASP\">\n";
    print OUTPUT "          <value>$PPN</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Tx_AGC\">\n";
    print OUTPUT "          <value>$TxA</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Rx_AGC0\">\n";
    print OUTPUT "          <value>$RxA0</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Rx_AGC1\">\n";
    print OUTPUT "          <value>$RxA1</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Cell\">\n";
    my $Tower;
    if ( $Towers{$Cell} ) {
      $Tower=$Towers{$Cell};
    } else {
      $Tower="Undefined";
    }
    print OUTPUT "          <value>$Cell ( $Tower )</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Sector\">\n";
    print OUTPUT "          <value>$Sector</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Flight Charts:\">\n";
    #my $FlightChart="http://performance.aircell.prod/reports/catalog/index.cgi?rm=details&tail=$Tail&date=$FlightDate2";
    my $FlightChart="&lt;a href=&quot;http://performance.aircell.prod/reports/catalog/index.cgi?rm=details&amp;tail=$Tail&amp;date=$FlightDate2&quot;&gt;View Charts&lt;/a&gt;&lt;br/&gt;&lt;br /&gt;";

#http://performance.aircell.prod/reports/catalog/index.cgi?rm=details&tail=$Tail&date=$FlightDate2";

    print OUTPUT "          <value>$FlightChart</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "      </ExtendedData>\n";
    print OUTPUT "      <Point>\n";
    print OUTPUT "        <altitudeMode>absolute</altitudeMode>\n";
    print OUTPUT "        <coordinates>$Lon,$Lat,$Alt</coordinates>\n";
    print OUTPUT "      </Point>\n";
    print OUTPUT "    </Placemark>\n";
  }
  print OUTPUT "  </Folder>\n";

  # Process Reboots
  print OUTPUT "  <Folder>\n";
  print OUTPUT "    <name>Reboots</name>\n";
  # Define the Styles ( which go in the MAPS ) for Reboots
  # UNKNOWN
  print OUTPUT "    <Style id=\"BA-Style-Reboot-Visible\">\n";
  print OUTPUT "      <IconStyle>\n";
  print OUTPUT "        <color>FF0000FF</color>\n";
  print OUTPUT "        <Icon>\n";
  print OUTPUT "          <href>http://maps.google.com/mapfiles/kml/pal3/icon39.png</href>\n";
  print OUTPUT "        </Icon>\n";
  print OUTPUT "        <scale>$IconScale</scale>\n";
  print OUTPUT "      </IconStyle>\n";
  print OUTPUT "      <LabelStyle>\n";
  print OUTPUT "        <scale>$LabelScale</scale>\n";
  print OUTPUT "      </LabelStyle>\n";
  print OUTPUT "      <BalloonStyle>\n";
  print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "      </BalloonStyle>\n";
  print OUTPUT "    </Style>\n";
  #
  print OUTPUT "    <Style id=\"BA-Style-Reboot-InVisible\">\n";
  print OUTPUT "      <IconStyle>\n";
  print OUTPUT "        <color>FF0000FF</color>\n";
  print OUTPUT "        <Icon>\n";
  print OUTPUT "          <href>http://maps.google.com/mapfiles/kml/pal3/icon39.png</href>\n";
  print OUTPUT "        </Icon>\n";
  print OUTPUT "        <scale>$IconScale</scale>\n";
  print OUTPUT "      </IconStyle>\n";
  print OUTPUT "      <LabelStyle>\n";
  print OUTPUT "        <scale>0</scale>\n";
  print OUTPUT "      </LabelStyle>\n";
  print OUTPUT "      <BalloonStyle>\n";
  print OUTPUT "        <bgColor>FFFFFFFF</bgColor>\n";
  print OUTPUT "      </BalloonStyle>\n";
  print OUTPUT "    </Style>\n";
  # Define Maps for the Colors
  # Reboots
  print OUTPUT "    <StyleMap id=\"BA-Style-Reboot-Map\">\n";
  print OUTPUT "      <Pair>\n";
  print OUTPUT "        <key>highlight</key>\n";
  print OUTPUT "        <styleUrl>#BA-Style-Reboot-Visible</styleUrl>\n";
  print OUTPUT "      </Pair>\n";
  print OUTPUT "      <Pair>\n";
  print OUTPUT "        <key>normal</key>\n";
  print OUTPUT "        <styleUrl>#BA-Style-Reboot-InVisible</styleUrl>\n";
  print OUTPUT "      </Pair>\n";
  print OUTPUT "    </StyleMap>\n";
  foreach my $Loop ( @RebootData ) {
    $Loop =~ /(\d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d,\d+) PowerReset: Latitude (.*), Longitude (.*), Altitude (.*), LastCell (.*), LastSector (.*), LastASA (.*)/;
    my $Time=$1;
    my $Lat=$2;
    my $Lon=$3;
    my $Alt=$4;
    my $Cell=$5;
    my $Sector=$6;
    my $ASA=$7;
    my $ASAStatus;
    print OUTPUT "    <Placemark>\n";
    my ( undef, $TS )=split(' ', $Time); 
    my ( $TSShort, undef )=split(',', $TS);
    print OUTPUT "      <styleUrl>#BA-Style-Reboot-Map</styleUrl>\n";
    print OUTPUT "      <name>Power Reset at $TSShort UTC </name>\n";
    print OUTPUT "  <LookAt id=\"\">\n";
    print OUTPUT "    <altitude>1</altitude>\n";
    print OUTPUT "    <heading>0</heading>\n";
    print OUTPUT "    <latitude>$Lat</latitude>\n";
    print OUTPUT "    <longitude>$Lon</longitude>\n";
    print OUTPUT "    <range>400000</range>\n";
    print OUTPUT "    <tilt>3</tilt>\n";
    print OUTPUT "  </LookAt>\n";
    my $TSMark=$Time;
    $TSMark =~ s/ /T/g;
    $TSMark =~ s/,\d+//;
    $TSMark =~ s/$/Z/g;
    print OUTPUT "      <TimeStamp><when>$TSMark></when></TimeStamp>\n";
    print OUTPUT "      <ExtendedData>\n";
    print OUTPUT "        <Data name=\"Time\">\n";
    print OUTPUT "          <value>$Time UTC </value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"ASA Status\">\n";
    if ( $ASA eq "T" ) {
      $ASAStatus="True";
    } else {
      $ASAStatus="True";
    }
    print OUTPUT "          <value>$ASA</value>\n";
    print OUTPUT "          <value>$ASAStatus</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Lat\">\n";
    print OUTPUT "          <value>$Lat</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Lon\">\n";
    print OUTPUT "          <value>$Lon</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Alt\">\n";
    print OUTPUT "          <value>$Alt</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Cell\">\n";
    my $Tower;
    if ( $Towers{$Cell} ) {
      $Tower=$Towers{$Cell};
    } else {
      $Tower="Undefined";
    }
    print OUTPUT "          <value>$Cell ( $Tower )</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "        <Data name=\"Sector\">\n";
    print OUTPUT "          <value>$Sector</value>\n";
    print OUTPUT "        </Data>\n";
    print OUTPUT "      </ExtendedData>\n";
    print OUTPUT "      <Point>\n";
    print OUTPUT "        <altitudeMode>absolute</altitudeMode>\n";
    print OUTPUT "        <coordinates>$Lon,$Lat,$Alt</coordinates>\n";
    print OUTPUT "      </Point>\n";
    print OUTPUT "    </Placemark>\n";
  }
  print OUTPUT "  </Folder>\n";
  # End of Reboots

  # Close the KML
  print OUTPUT "</Document>\n";
  print OUTPUT "</kml>\n";
  close(OUTPUT);
#print "/bin/rm -f $TargetFile; /usr/bin/zip -q -9 $TargetFile $TmpFile && /bin/rm $TmpFile\n";
  system("/bin/rm -f $TargetFile; /usr/bin/zip -q -9 $TargetFile $TmpFile && /bin/rm $TmpFile");
  #system("/bin/rm -f $TargetFile; /usr/bin/zip -q -9 $TargetFile $TmpFile");
}


sub Define_Towers {
  %Towers= (
	'0130' => 'AK001',
	'0131' => 'AK002',
	'0132' => 'AK003',
	'0133' => 'AK004',
	'0134' => 'AK005',
	'0135' => 'AK006',
	'0082' => 'AL001',
	'0031' => 'AL002',
	'0094' => 'AL003',
	'0095' => 'AL004',
	'0004' => 'AR001',
	'0113' => 'AR002',
	'0114' => 'AR003',
	'0103' => 'AR004',
	'0067' => 'AZ001',
	'0090' => 'AZ002',
	'0104' => 'AZ003',
	'0021' => 'AZ004',
	'0129' => 'AZ006',
	'0121' => 'CA002',
	'0012' => 'CA003',
	'0074' => 'CA004',
	'0034' => 'CA005',
	'0085' => 'CA006',
	'0170' => 'CA007',
	'0115' => 'CA008',
	'0062' => 'CA009',
	'0105' => 'CA010',
	'0029' => 'CO001',
	'0087' => 'CO002',
	'0058' => 'CO003',
	'0049' => 'CO004',
	'0088' => 'CO005',
	'0096' => 'CO006',
	'0155' => 'CO007',
	'0120' => 'CO008',
	'0054' => 'FL001',
	'0077' => 'FL002',
	'0064' => 'FL003',
	'0026' => 'FL004',
	'0106' => 'FL005',
	'0156' => 'FL006',
	'0220' => 'FL007',
	'0136' => 'FL008',
	'0193' => 'FL009',
	'0010' => 'GA001',
	'0048' => 'GA002',
	'0107' => 'GA003',
	'0108' => 'GA004',
	'0101' => 'GA005',
	'0007' => 'IA001',
	'0126' => 'IA002',
	'0148' => 'IA003',
	'0187' => 'IA004',
	'0020' => 'ID001',
	'0072' => 'ID002',
	'0092' => 'ID003',
	'0001' => 'IL001',
	'0102' => 'IL002',
	'0111' => 'IL003',
	'0144' => 'IL004',
	'0157' => 'IL005',
	'0005' => 'IN001',
	'0119' => 'IN002',
	'0110' => 'IN003',
	'0038' => 'KS001',
	'0039' => 'KS002',
	'0122' => 'KS003',
	'0123' => 'KS004',
	'0207' => 'KS005',
	'0150' => 'KS006',
	'0209' => 'KS007',
	'0137' => 'KS008',
	'0057' => 'KY001',
	'0186' => 'KY002',
	'0153' => 'KY003',
	'0128' => 'KY004',
	'0041' => 'LA001',
	'0047' => 'LA002',
	'0081' => 'LA003',
	'0177' => 'LA004',
	'0053' => 'MA001',
	'0070' => 'MD001',
	'0154' => 'MD002',
	'0014' => 'ME001',
	'0055' => 'MI001',
	'0046' => 'MI002',
	'0024' => 'MI003',
	'0145' => 'MI004',
	'0149' => 'MI005',
	'0139' => 'MI006',
	'0056' => 'MN001',
	'0169' => 'MN002',
	'0003' => 'MO001',
	'0124' => 'MO002',
	'0125' => 'MO003',
	'0206' => 'MO004',
	'0160' => 'MO005',
	'0188' => 'MO006',
	'0033' => 'MS001',
	'0178' => 'MS002',
	'0036' => 'MT001',
	'0016' => 'MT002',
	'0189' => 'MT003',
	'0008' => 'NC001',
	'0086' => 'NC002',
	'0152' => 'NC003',
	'0080' => 'ND001',
	'0059' => 'NE001',
	'0052' => 'NE002',
	'0097' => 'NE003',
	'0142' => 'NE004',
	'0159' => 'NE005',
	'0127' => 'NE006',
	'0084' => 'NJ001',
	'0028' => 'NM001',
	'0023' => 'NM002',
	'0063' => 'NM003',
	'0099' => 'NM004',
	'0161' => 'NM005',
	'0143' => 'NM006',
	'0151' => 'NM007',
	'0197' => 'NM008',
	'0051' => 'NV001',
	'0078' => 'NV002',
	'0065' => 'NV003',
	'0030' => 'NV004',
	'0172' => 'NV005',
	'0037' => 'NY001',
	'0083' => 'NY002',
	'0208' => 'NY004',
	'0042' => 'OH001',
	'0109' => 'OH002',
	'0158' => 'OH003',
	'0163' => 'OH004',
	'0271' => 'OK001',
	'0060' => 'OK002',
	'0116' => 'OK003',
	'0117' => 'OK004',
	'0098' => 'OK005',
	'0167' => 'OK007',
	'0022' => 'OR001',
	'0069' => 'OR002',
	'0050' => 'PA001',
	'0100' => 'PA002',
	'0183' => 'PA003',
	'0071' => 'PA004',
	'0168' => 'PA005',
	'0061' => 'SC001',
	'0015' => 'SC002',
	'0211' => 'SC003',
	'0194' => 'SC004',
	'0017' => 'SD001',
	'0009' => 'SD002',
	'0164' => 'SD003',
	'0190' => 'SD004',
	'0006' => 'TN001',
	'0091' => 'TN002',
	'0179' => 'TN003',
	'0213' => 'TN005',
	'0027' => 'TX001',
	'0043' => 'TX002',
	'0011' => 'TX003',
	'0166' => 'TX004',
	'0040' => 'TX005',
	'0032' => 'TX006',
	'0165' => 'TX007',
	'0182' => 'TX009',
	'0118' => 'TX010',
	'0112' => 'TX011',
	'0147' => 'TX012',
	'0184' => 'TX013',
	'0204' => 'TX014',
	'0076' => 'UT001',
	'0089' => 'UT002',
	'0035' => 'UT003',
	'0191' => 'UT007',
	'0173' => 'UT008',
	'0192' => 'UT009',
	'0079' => 'VA001',
	'0013' => 'VA002',
	'0210' => 'VA003',
	'0185' => 'VA004',
	'0181' => 'VA005',
	'0075' => 'WA001',
	'0045' => 'WA002',
	'0068' => 'WA003',
	'0019' => 'WI001',
	'0162' => 'WI002',
	'0140' => 'WI003',
	'0044' => 'WV001',
	'0093' => 'WY001',
	'0025' => 'WY002',
	'0018' => 'WY003',
	'0146' => 'WY004',
	'0203' => 'YY203',
	'0212' => 'YY212',
	'0244' => 'YY244',
	'0250' => 'YY250'
  );
}



