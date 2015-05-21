#!/usr/bin/perl -w
$| = 1;

#
# We are merging many logs into 1 for processing.
#
# There can be only one!
#
use Env;
use strict;
use diagnostics;
use Date::Calc qw(:all);
use File::Basename;
use strict;
use diagnostics;
use Date::Calc qw(:all);
use Date::Manip;
use Class::Date;
use Time::Local;
use POSIX 'strftime';
 

my $User=$ENV{"LOGNAME"};
my $PID=$$;

# GetOpt
use vars qw( $opt_h $opt_v $opt_F $opt_T $opt_t $opt_f $opt_so $opt_fc $opt_fm $opt_fsm $opt_year $opt_sy $opt_fy $opt_m $opt_sm $opt_fm $opt_d $opt_sd $opt_fd $opt_st $opt_ft $opt_p $opt_nocomp $opt_all $opt_console $opt_airlink $opt_gatekeeper  $opt_messages $opt_fum $opt_drift $opt_na $opt_nac $opt_nas $opt_nam );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v F T=s y=s sy=s fy=s m=s sm=s fm=s d=s sd=s fd=s st=s ft=s p=s t f=s so fc=s fm=s fsm=s nocomp all console airlink gatekeeper messages fum drift na nac nas nam");

# If someone does --na, disable all auto-loads
if ( $opt_na ) {
  $opt_nac=1;
  $opt_nas=1;
  $opt_nam=1;
}

#
# Declare Variables
#
#
my $Verbose=$opt_v;
my $LastLine="";
#
my %NetOpsNotes;
my @XPOL;
# ATG Time Drift Calculations
my $HaveDrift=0;
my $DriftChange=0;
my $Drift="0";
my $DriftLast="1";
my $LastDrift="1";
my $Year; my $Mon; my $Day; my $Hour; my $Min; my $Sec; my $Mili;
my $year; my $month; my $day; my  $hour; my $min; my $sec;
# 
my $Line; my $Loop; my $LogKey;
my $Target;
my $Tail; my $Continue=0;
my %Mons; my %RMons; my @Days;
#
# Date Values
#
my $StartYear; my $StartMon; my $StartDay; my $StartHour="00"; my $StartMin="00"; my $StartSec="00"; my $StartTime;
my $FinishYear; my $FinishMon; my $FinishDay; my $FinishHour="23"; my $FinishMin="59"; my $FinishSec="59"; my $FinishTime;
my $DiffYears; my $DiffMons; my $DiffDays; my $DiffHours; my $DiffMins; my $DiffSecs;
#
# ATG Console Specific Values
my @ATGConsoleFiles; 
my @ATGSMFiles; 
my @ATGMessageFiles; 
my $ConsoleLogs=0;
# Time Drift Values
my %ATGLines;
my @LogLines;
my $GPS_TIME;
my @GPS_Time_Diff;
my $ATGBase="/opt/log/atg/";
# ATG SM Specific
my $PushLine=0;


if ( $opt_h ) {
  print "\n\n";
  print "Usage:  extract_one_log.pl <options>\n";
  print " -h = help (This screen)\n";
  print " --all = Process all the log types.\n";
  print " --console = Process the ATG console logs.\n";
  print " --airlink = Process the ATG Airlink (SM) logs.\n";
  print " --gatekeeper = Process the ATG gatekeeper logs.\n";
  print " --messages = Process the ATG messages logs.\n";
  print "\n";
  print "Options: \n";
  print "  -v = Verbose output. This may get messy...\n";
  print "  -F = Show the files being processed.\n";
  print "  -T <TAIL> = Specify a Tail to build the logfile for.  REQUIRED\n";
  print "  -t = Create the correlation file in /tmp with the user name.  i.e. /tmp/highlander-rharris.log\n";
  print " --na = Do not automatically find files ( Mostly used with force loads of individual fils )\n";
  print " --nocomp = Do not perform Time Drift compensation\n";
  print " --drift = Show how much the clock drifted and when in NetOps Notes.\n";
  print " --so = Write the correlated log files to standard out\n";
  print " --fc <Files> = Force a list of console files to read. ( Comma separated, no spaces )\n";
  print " --fm <Files> = Force a list of message files to read. ( Comma separated, no spaces )\n";
  print " --fsm <Files> = Force a list of SM files to read. ( Comma separated, no spaces )\n";
  print "  -p <PATH> = Create the correlation file in <PATH> with the user name.\n";
  print "\n";
  print "Date Options:\n";
  print "  If the Year, Month and Day values are omited, it will default to the current.\n";
  print "  If the Starting Year, Month and Day are the same the singular ( -y, -m -d ) will fill in for the multiples.\n";
  print "    -y 2014 -m 04 -d 02   ==  --sy 2014 --fy 2014 --sm 04 --fm 04 --sd 02 --fd 02\n";
  print "  In order to get all log files starting with 04/03/2014 thourgh (and including) 04/25/2014) use:\n";
  print "    -y 2014 -m 04 -d 03 --sy 2014 --fy 2014 --sm 25 --fm 04 --sd 02 --fd 02\n";
  print "  ***\n";
  print "  -y <YYYY> = Specify a year start/finish. \n";
  print " --sy <YYYY> = Specify a starting year.  \n";
  print " --fy <YYYY> = Specify a finish year.  \n";
  print "\n";
  print "  -m <MM> = Specify a month start/finish.  \n";
  print " --sm <MM> = Specify a starting month.\n";
  print " --fm <MM> = Specify a finish month.\n";
  print "\n";
  print "  -d <DD> = Specify a day start/finish.\n";
  print " --sd <DD> = Specify a starting day.\n";
  print " --fd <DD> = Specify a finish day.\n";
  print " --st <HH:MM:SS> = Specify a starting time.\n";
  print " --ft <HH:MM:SS> = Specify a finish time.\n";
  print "\n";
  print "  ** ASTERISKS MUST BE QUOTED OR IT WILL NOT WORK RIGHT!!! **\n";
  print "\n\n";
  exit 0;
}

# If --all is selected, turn on the other log types.
if ( $opt_all ) {
  $opt_console=1;
  $opt_airlink=1;
  $opt_messages=1;
}

$Continue="1" if ( $opt_console );
$Continue="1" if ( $opt_airlink );
$Continue="1" if ( $opt_messages );
# Force Continue if we manually specify a log to parse ( UCS, manual send, etc )
# - ATG
if ( $opt_fc ) {
  $Continue="1";
  $opt_T="Manual" unless ( $opt_T );
}
if ( $opt_fm ) {
  $Continue="1";
  $opt_T="Manual" unless ( $opt_T );
}
if ( $opt_fsm ) {
  $Continue="1";
  $opt_T="Manual" unless ( $opt_T );
}
# - UCS
$Continue="1" if ( $opt_fum );

if ( ! $Continue ) {
  print "\n";
  print "You must specify a type of log to process.  ( See -h for help )\n";
  print "\n";
  exit 0;
}

&Define_Months;
&Define_Parameters;


print "Start: $StartYear, $StartMon, $StartDay, $StartHour, $StartMin, $StartSec\n" if ( $Verbose );
my $StartStamp=&ConvertManualTimeStamp( $StartYear, $StartMon, $StartDay, $StartHour, $StartMin, $StartSec );
print "Finish: $FinishYear, $FinishMon, $FinishDay, $FinishHour, $FinishMin, $FinishSec\n" if ( $Verbose );
my $FinishStamp=&ConvertManualTimeStamp( $FinishYear, $FinishMon, $FinishDay, $FinishHour, $FinishMin, $FinishSec );

my $Start=$StartYear.$StartMon.$StartDay;
my $Finish=$FinishYear.$FinishMon.$FinishDay;

print "\n";
print "Extracting Tail $Tail Starting with $StartYear/$StartMon/$StartDay through $FinishYear/$FinishMon/$FinishDay to $Target\n";

$Start=$StartYear.$StartMon.$StartDay;
$Finish=$FinishYear.$FinishMon.$FinishDay;

&Log_Commands;

if ( ! $Year ) {
  $Year=`/bin/date +%Y`; chomp( $Year );
}

foreach my $Loop ( $opt_sm..$opt_fm ) {
  print "Processing Month :$Loop:\n" if ( $Verbose );

  my $Dir="/opt/log/atg/".$Year."/".$Loop;

  print "\$Dir :$Dir:\n" if ( $Verbose );
  chdir("$Dir");
  if ( ( $opt_console ) || ( $opt_fc ) ) {
    &ListATGConsoleFiles;
    &ImportATGConsoleFiles;
  }

  if ( $opt_messages ) {
    &ListATGMessagesFiles;
    &ImportATGMessagesFiles;
  }
  # SortLoglines to fold in messages and console
  @LogLines=sort(@LogLines);
  # Lets fix our drift after importing them all
  @LogLines=&Fix_Drift(@LogLines);

  # Lets import SM/Airlink now that we've fixed drift since they don't need to be 'fixed'
  if ( $opt_airlink ) {
    &ListATGSMFiles;
    &ImportATGSMFiles;
  }

  # Re-sort now that Airlink is included 
  @LogLines=sort(@LogLines);
}


&WriteCorrelationLog if ( $#LogLines > 0 );



########################
# Sub-Procs below here #
########################
sub ListATGConsoleFiles {
  # Define the list of ATG Console files to read in.

  if ( $opt_console ) {
    # Lets find the location of our log files
    my $FileList=$ATGBase.$StartYear."/".$StartMon."/".$Tail."/abs_logs/acpu_java/*.console.log.tar.gz";

    # Skip this unless --na ( No Auto ) is NOT specified
    if ( ! $opt_nac ) {
      # Lets get potential file list.
      print "Getting File List from $FileList\n" if ( $Verbose );
      open(INPUT, "ls -1 $FileList |");
      while(<INPUT>) {
        chomp;
        #  13512.2014-03-31-19-35-01.console.log.tar.gz
        ($Year, $Mon, $Day, undef)=split('-', $_);
        (undef, $Year)=split('\.', $Year);
    
        print "* Going to process $_\n" if ( $Verbose );
    
        push(@ATGConsoleFiles, $_);
      }
      close(INPUT);
    }
  }
  if ( $opt_fc ) {
    foreach $Loop (split(',', $opt_fc)) {
      print "Pushing $Loop to \@ATGConsoleFiles\n" if ( $Verbose );
      push(@ATGConsoleFiles, $Loop);
    }
  }
}


sub ListATGSMFiles {

  # Lets find the location of our log files
  my $FileList=$ATGBase.$StartYear."/".$StartMon."/".$Tail."/sm/*SM.tar.gz";

  # Skip this unless --na ( No Auto ) is NOT specified
  if ( ! $opt_nas ) {
    # Lets get potential file list.
    print "Getting File List from $FileList\n" if ( $Verbose );
    open(INPUT, "ls -1 $FileList 2>/dev/null |");
    while(<INPUT>) {
      chomp;
      ($Year, $Mon, $Day, undef)=split('-', $_);
      (undef, $Year)=split('\.', $Year);
  
      print "Adding $_.\n" if ( $opt_F || $Verbose );
      push(@ATGSMFiles, $_);
  
    }
    close(INPUT);
  }
  if ( $opt_fsm ) {
    foreach $Loop (split(',', $opt_fsm)) {
      print "Pushing $Loop to \@ATGConsoleFiles\n" if ( $Verbose );
      push(@ATGConsoleFiles, $Loop);
    }
  }
}


sub ListATGMessagesFiles {
  # Define the list of ATG Console files to read in.

  if ( $StartMon != $FinishMon ) {
    # Have to get the file list from multimple months.
    # Have to implement that still.
    print "\n";
    print "Multiple Months not implemented yet.\n";
    print "\n";
    exit 0;
  }

  # Lets find the location of our log files
  my $FileList=$ATGBase.$StartYear."/".$StartMon."/".$Tail."/abs_logs/acpu_linuxsys/*.messages.tar.gz";
  # ** Because of how Messages are stored and uploaded, we might need to look into next month
  my $FileListNext=$ATGBase.$StartYear."/".$StartMon."/".$Tail."/abs_logs/acpu_linuxsys/*.messages.tar.gz";

  # Skip this unless --na ( No Auto ) is NOT specified
  if ( ! $opt_nam ) {
    # Lets get potential file list.
    print "Getting File List from $FileList\n" if ( $Verbose );
    #open(INPUT, "ls -1 $FileList |");
    open(INPUT, "/bin/find $FileList $FileListNext -type f |");
    while(<INPUT>) {
      chomp;
  
      print "* Going to process $_\n" if ( $Verbose );
  
      push(@ATGMessageFiles, $_);
  
    }
    close(INPUT);
  }
  if ( $opt_fm ) {
    foreach $Loop (split(',', $opt_fm)) {
      print "Pushing $Loop to \@ATGConsoleFiles\n" if ( $Verbose );
      push(@ATGConsoleFiles, $Loop);
    }
  }
}


sub ImportATGConsoleFiles {
  # Read the Defined list of Console files into memory for processing
  my $TimeStamp; my $Message;
  my $Mili=0; my $MiliTmp="";

  # Lets load the Console Log into memory to process
  print "Getting list of ATG Console Files.\n" if ( $opt_F );
  foreach $Loop ( sort ( @ATGConsoleFiles ) ) {
    my $FileLineCount=0;
    $ConsoleLogs++;
    print "  Importing $Loop\n" if ( ( $opt_F ) || ( $opt_fc ) );
    print "  * tar xzvOf $Loop\n";
    open(INPUT, "tar xzvOf $Loop 2>&1 |");
    while(<INPUT>) {
      chomp;
      next if ( /^$/ );
      next if ( /^console.log/ );
 
      # Get rid of known garbage
      next if ( $_ =~ /Received Message : FILE_ADDED_IN_STAGING_AREA/ );

      $Line=$_;
      $Line =~ s/[^[:print:]]//g;
      $Line =~ s/\[Thread-\d+\]//g;

      # Remove Duplicate Lines
      next if ( $LastLine eq $Line );
      # Update Last to current for next test
      $LastLine=$Line;

      next unless $Line =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+/;
      $Line =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,\d+) (.*)/;
        $TimeStamp=$1;
        $Message=$2;
      $Line="$TimeStamp Console: $Message";
      $Line=&ConvertATGTimeStamp( $Line );
      push(@LogLines, $Line);
      $FileLineCount++;
     
      # Log changes to Drift
      my $DriftChange=$Drift-$LastDrift;
      if ( abs($DriftChange) > 60 ) {
        my $DriftLine="$TimeStamp Drift: $Drift";
        push(@LogLines, $DriftLine);
        $LastDrift=$Drift;
        $FileLineCount++;
      }
    }
    print "Loaded $FileLineCount lines.\n" if ( $Verbose );
  }

  print "Done Cleaning timestamp format.\n" if ( ( $Verbose ) || ( $opt_F ));
  
  $NetOpsNotes{"0005-Console"}="We found $ConsoleLogs Console logs to process.";
}


sub ImportATGSMFiles {
  # Read the Defined list of Airlink (SM) files into memory for processing
  my $TimeStamp; 
  my $Message;
  my $Lat; my $Lon; my $Alt; 
  #
  $PushLine=0;
  my $Mili=0; my $MiliTmp="";

  print "Getting list of ATG SM Files.\n" if ( $opt_F );

  # Lets load the SM Log into memory to process
  foreach $Loop ( sort ( @ATGSMFiles ) ) {
    my $FileLineCount=0;
    print "  Importing $Loop\n" if ( $opt_F );
    open(INPUT, "tar xzvOf $Loop \"*_Airlink.txt\"  2>&1 |");
    while(<INPUT>) {
      chomp;
      next if ( /^$/ );
      next if ( /^console.log/ );
      $Line=$_;

      # Remove non-printable characters ( NOT the whole line )
      $Line =~ s/[^[:print:]]//g;
  
      # Remove duplicate lines
      $Line=$_;

      # Remove Duplicate Lines
      next if ( $LastLine eq $Line );
      # Update Last to current for next test
      $LastLine=$Line;

      # Skip empty Lines
      next if ( $Line =~ /^$/ );

      $FileLineCount++;

      # New Data Block.  Push the previous Line and start over
      if ( $Line =~ /^\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,.*,.*,.*/ ) {
        $Line =~ /^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d),/;
          $TimeStamp=$1;
        $TimeStamp=&ConvertATGSMTimeStamp( $TimeStamp );

        $PushLine="$TimeStamp Airlink: $PushLine" if ( $PushLine );
        push(@LogLines, $PushLine) if ( $PushLine );
        $PushLine=0;
        &Process_SM_DATEGPS("$Line");
      }
      &Process_SM_DRC("$Line") if ( /^DRC_BUFFER/ );
      &Process_TX_AGC("$Line") if ( /^Tx_AGC/ );
      &Process_RX_AGC("$Line") if ( /^Rx_AGC/ );
      &Process_Pilot_PN("$Line") if ( /^PILOT_PN_ASP/ );
      &Process_SM_Sector_ID("$Line") if ( /^Serving_SectorID/ );
      #&Process_SM_SINR("$Line") if ( /^ASP_FILTERED_SINR/ );
      &Process_SM_SINR("$Line") if ( /^BEST_ASP_SINR_BUFFER/ );
    }
    print "Loaded $FileLineCount lines.\n" if ( $Verbose );
  }
}


sub ImportATGMessagesFiles {
  # Read the Defined list of Message files into memory for processing
  my $TimeStamp; my $Message;
  my $LastMessage="";
  my $year; my $month; my $day; my  $hour; my $min; my $sec;
  $Year=$StartYear;
  my $TMon;
  my $Mili=0000000; my $MiliTmp=0;

  print "Getting list of ATG Messages Files.\n" if ( $opt_F );

  # Lets load the Message Log into memory to process
  foreach $Loop ( sort ( @ATGMessageFiles ) ) {
    my $FileLineCount=0;
    print "  Importing $Loop\n" if ( $opt_F );
    open(INPUT, "tar xzvOf $Loop 2>&1 |");
    while(<INPUT>) {
      chomp;
      next if ( /^$/ );
      next if ( /^console.log/ );

      $Line=$_;

      # Remove Duplicate Lines
      next if ( $LastLine eq $Line );

      # Update Last to current for next test
      $LastLine=$Line;

      $Line =~ s/[^[:print:]]//g;

      next unless $Line =~ /^\w\w\w +\d+ \d\d:\d\d:\d\d ATG4K /;
      $Line =~ /(\w+) *(\d+) *(\d\d):(\d\d):(\d\d) (.*)/;
      $TMon=$1;
      $Day=$2;
      $Hour=$3;
      $Min=$4;
      $Sec=$5;
      $Message=$6;

      $Mon=$RMons{$TMon};
      $Day=substr("0"."$Day", -2);
      $Hour=substr("0"."$Hour", -2);
      $Min=substr("0"."$Min", -2);
      $Sec=substr("0"."$Sec", -2);
      $MiliTmp=0 if ( $MiliTmp eq "" );
      $TimeStamp=$Year."-".$Mon."-".$Day." $Hour:$Min:$Sec";
      if ( $TimeStamp !~ /,\d+/ ) {
        if ( $MiliTmp eq $TimeStamp ) {
          $Mili++;
        } else {
          $Mili = 0;
          $MiliTmp=$TimeStamp;
        }
        $Mili=substr("$Mili"."000000", 0, 6);
        $TimeStamp=$TimeStamp.",".$Mili;
      }
      $Line="$TimeStamp Messages: $Message";
      $Line=&ConvertATGTimeStamp( $Line );
      $FileLineCount++;

      push( @LogLines, $Line);
    }
    print "Loaded $FileLineCount lines.\n" if ( $Verbose );
  }

  print "Done cleaning timestamp format.\n" if ( ( $Verbose ) || ( $opt_F ));
}


sub Process_SM_DATEGPS {
  # Lets build the Airlink Lines for Datestamp and GPS Information
  my $Line=$_[0];
  my $TimeStamp; 
  my $Lat; my $Lon; my $Alt; 

  if ( $Line =~ /\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d,-*\d+\.\d+,-*\d+\.\d+,\d+/ ) {

    $Line =~ /(\d\d\d\d\-\d\d-\d\d \d\d:\d\d:\d\d),(-*\d+\.\d+),(-*\d+\.\d+),(\d+)/;
    $TimeStamp=$1;
    $Lat=$2;
    $Lon=$3;
    $Alt=$4;

    $PushLine="Latitude $Lat : Longitude $Lon : Altitude $Alt";
  }
}


sub Process_SM_DRC {
  # Lets add the DRC information to our Airlink lines
  my $Line=$_[0];

  $Line =~ s/,//;
  $Line =~ s/ +$//;

  $PushLine .= ", $Line";
}


sub Process_TX_AGC {
  # Lets add the TXA GC information to our Airlink lines
  my $Line=$_[0];

  $Line =~ s/,//;
  $Line =~ s/ +$//;

  $PushLine .= ", $Line";
}


sub Process_Pilot_PN {
  # Lets add the Pilot PN ASP information to our Airlink lines
  my $Line=$_[0];

  $Line =~ s/,//;
  $Line =~ s/ +$//;

  $PushLine .= ", $Line";
}


sub Process_RX_AGC {
  # Lets add the RX AGC information to our Airlink lines
  my $Line=$_[0];

  $Line =~ s/,//;
  $Line =~ s/ +$//;

  $PushLine .= ", $Line";
}


sub Process_SM_Sector_ID {
  # Lets add the SectorID information to our Airlink lines
  my $Line=$_[0];
  $Line =~ s/ +$//g;

  my $SectorLine;


  if ( $Line =~ /Serving_SectorID, \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d \d\d$/ ) {
    $Line =~ /Serving_SectorID, 00 00 00 00 00 00 00 00 00 00 00 00 00 (\d\d) (\d\d) (\d\d)$/;
    my $Cell1=$1;
    my $Cell2=$2;
    my $Cell="$1"."$2";
    my $Sector=$3;
    $SectorLine = ", Cell $Cell, Sector $Sector";
  } elsif ( $Line =~ /Serving_SectorID, \d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d\d$/ ) {
    $Line =~ /Serving_SectorID, 00000000000000000000000000(\d\d)(\d\d)(\d\d)$/;
    my $Cell1=$1;
    my $Cell2=$2;
    my $Cell="$1"."$2";
    my $Sector=$3;
    $SectorLine = ", Cell $Cell, Sector $Sector";
  } else {
    $SectorLine = ", Cell 99999, Sector 99999";
  }
  $PushLine .= $SectorLine;
}


sub Process_SM_SINR {
  # Lets add the SectorID information to our Airlink lines
  my $Line=$_[0];

  $Line =~ s/,//;

  $PushLine .= ", $Line";
}


sub WriteCorrelationLog {
  my $Written=0;
  my $LastMessage="";
 
  # Write out our final file
  print "Processing $#LogLines lines of data\n" if ( $Verbose );
  open(OUTPUT, ">$Target") || die "\n\nCouldn't open $Target :$!:\n\n";

  # Lets dump our specific Notes:
  foreach $Loop ( sort ( keys ( %NetOpsNotes ) ) ) {
    print OUTPUT $Loop."::NetOps Note: $NetOpsNotes{$Loop}\n";
  }

  print OUTPUT "\n\n";

  my $Tmp=$#LogLines+1;
  print "Prepping to write $Tmp lines.\n" if ( $Verbose );
  foreach $Loop ( sort ( @LogLines ) ) {
    $Loop =~ /(\d+\.\d+) (.*)/;
    my $TS=$1;
    my $Message=$2;
    # Lets De-Dupe
    next if ( $Message eq $LastMessage);
    $LastMessage=$Message;
    next unless ( ( $TS > $StartStamp ) && ( $TS < $FinishStamp ));
    $TS=&ConvertReadableTimeStamp($TS);
    print OUTPUT "$TS $Message\n";
    $Written++;
  }
  close(OUTPUT);
  print "Wrote ".$Written." relevant lines of data, out of $#LogLines  to $Target\n";
}


sub GPS_Time_Diff {
  # How badly is our timestamp hosed?
  my $ATG; my $GPS; my $GPS_Time;

  $GPS_Time=$_[0];

  $GPS_Time =~ /(\d+\.\d+) Console: \- .*GPS TIME +(.*)/;
  
  $ATG=$1;
  $GPS=&ConvertGPSTimeStamp($2);

  $ATG =~ s/\.\d+//;

  my $Drift=$ATG-$GPS;

  return( $Drift );

}


sub Process_GPS_Time {
  # How badly is our timestamp hosed?
  my $GPS_Line=$_[0];

  $HaveDrift=1;
  my $Drift=&GPS_Time_Diff("$GPS_Line");

  my $DriftChange=$Drift-$DriftLast;
  if ( abs($DriftChange) > 60 ) {
    $NetOpsNotes{"0002-ATG GPS Time Entry"}=$GPS_Line;
    $NetOpsNotes{"0003-ATG GPS"}="Compensating for drift";
  
    my $TimeLine = "ATG Time off by $Drift seconds";
  
    if ( $Drift ne $DriftLast ) {
      if ( $opt_drift ) {
        $NetOpsNotes{"0004-$DriftChange-ATG GPS Time Differential"}=$TimeLine;
      } else {
        $NetOpsNotes{"0004-ATG GPS Time Differential"}="Drift changed $DriftChange times.  Last value $TimeLine";
      }
      $DriftChange++;
      $DriftChange=substr("00"."$DriftChange", -3);
      print "Updated Drift $DriftChange : $TimeLine\n" if ( $Verbose );
      print "  Short $Drift\n" if ( $Verbose );
      print "  Last $DriftLast\n" if ( $Verbose );
      $DriftLast = $Drift;
    }
  }
  return( $Drift );
}


sub Fix_Drift {
  my (@Lines)=@_;
  my (@LogLines);

  foreach my $Line ( @Lines ) {
#print "Drift \$Line :$Line:\n";

    # Lets find our Drift
    $Drift=&Process_GPS_Time("$Line") if ( ( $Line =~ /GPS TIME/) && ( !  $NetOpsNotes{"ATG GPS Time Entry"} ));
    $Line =~ /(\d+\.\d+) (.*)/;
    my $TimeStamp=$1;
    my $Message=$2;

    my ( $Time, $Mili )=split('\.', $TimeStamp);
    $Mili="000000" if ( ! $Mili );
    $Mili=substr("$Mili"."000000", 0, 6);
    $TimeStamp=$Time.".".$Mili;
  
    $Line=$TimeStamp." ".$Message;
  
    push(@LogLines, $Line);
  }
  return(@LogLines);
}


sub Log_Commands {
  $NetOpsNotes{"0001-Tail"}="Extracting Tail $Tail Starting with $StartYear/$StartMon/$StartDay $StartTime through $FinishYear/$FinishMon/$FinishDay $FinishTime to $Target";
}
 

sub Define_Months {
  @Days = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
  %Mons = ("01"=>'Jan',"02"=>'Feb',"03"=>'Mar',"04"=>'Apr',"05"=>'May',"06"=>'Jun',"07"=>'Jul',"08"=>'Aug',"09"=>'Sep',"10"=>'Oct',"11"=>'Nov',"12"=>'Dec');
  %RMons = ("Jan"=>'01',"Feb"=>'02',"Mar"=>'03',"Apr"=>'04',"May"=>'05',"Jun"=>'06',"Jul"=>'07',"Aug"=>'08',"Sep"=>'09',"Oct"=>'10',"Nov"=>'11',"Dec"=>'12');
}
 

sub Define_Parameters {
  # Lets nail down some options:  $Tail, target paths and our dates
  if ( ! $opt_T ) {
    print "\n";
    print "You must specify a tail. ( -T XXXXX )\n";
    print "\n";
    exit 0;
  } else {
    $Tail=$opt_T;
  }
  
  if ( $opt_p ) {
    $Target=$opt_p."/highlander-".$User.".log";
    if ( ! -d $opt_p ) {
      mkdir( $opt_p);
    }
  } elsif ( $opt_f ) {
    $Target=$opt_f;
  } elsif ( $opt_t ) {
    $Target="/tmp/highlander-".$User.".log";
  } elsif ( $opt_so ) {
    $Target="-";
  } else {
    $Target="highlander.log";
  }

  #
  # Fix dates here
  #
  # Years
  if ( $opt_year ) {
    $opt_sy=$opt_year;
    $opt_fy=$opt_year;
    #$Year=$opt_year;
  }
  # Lets get our starting and finishing year
  if ( $opt_sy ) {
    $StartYear=$opt_sy;
    $StartYear=substr("20"."$StartYear", -4) if ( $StartYear =~ /^\d\d$/ );
  } else {
    $StartYear=`/bin/date +%Y`;
    chomp($StartYear);
  }
  if ( $opt_sy ) {
    $FinishYear=$opt_sy;
  } else {
    $FinishYear=`/bin/date +%Y`;
    $FinishYear=substr("20"."$FinishYear", -4) if ( $FinishYear =~ /^\d\d$/ );
    chomp($FinishYear);
  }

  if ( $StartYear != $FinishYear ) {
    print "\n";
    print "Not handling multi-year yet.  Try again or do it manually.\n";
    print "\n";
    exit 0;
  }

  # Months
  my $Month=`/bin/date +%m`; chomp( $Month );
  if ( $opt_m ) {
    $opt_sm=$opt_m;
    $opt_fm=$opt_m;
  }
  # Lets get our starting and finishing month
  if ( $opt_sm ) {
    $StartMon=$opt_sm;
    $StartMon=substr("0"."$StartMon", -2) if ( $StartMon =~ /^\d$/ );
  } else {
    $StartMon=`/bin/date +%m`;
    chomp($StartMon);
  }
  if ( $opt_fm ) {
    $FinishMon=$opt_fm;
    $FinishMon=substr("0"."$FinishMon", -2) if ( $FinishMon =~ /^\d$/ );
  } else {
    $FinishMon=`/bin/date +%m`;
    chomp($FinishMon);
  }
  if ( $StartMon > $Month ) {
    $Year--;
    $StartYear--;
    $FinishYear--;
  }

  # Days
  if ( $opt_d ) {
    $opt_sd=$opt_d;
    $opt_fd=$opt_d;
  }
  # Lets get our starting and finishing days
  if ( $opt_sd ) {
    $StartDay=$opt_sd;
    $StartDay=substr("0"."$StartDay", -2) if ( $StartDay =~ /^\d$/ );
  } else {
    $StartDay=`/bin/date +%d`;
    chomp($StartDay);
  }
  if ( $opt_fd ) {
    $FinishDay=$opt_fd;
    $FinishDay=substr("0"."$FinishDay", -2) if ( $FinishDay =~ /^\d$/ );
  } else {
    $FinishDay=`/bin/date +%d`;
    chomp($FinishDay);
  }
  # Lets get our starting and finishing time
  if ( $opt_st ) {
    $StartTime=$opt_st;
  } else {
    $StartTime="00:00:00";
  }
  if ( $opt_ft ) {
    $FinishTime=$opt_ft;
  } else {
    $FinishTime="23:23:59";
  }
}


sub ConvertManualTimeStamp {
  my $Year=$_[0];
  my $Mon=$_[1];
  my $Day=$_[2];
  my $Hour=$_[3];
  my $Min=$_[4];
  my $Sec=$_[5];
  my $Time;


  my $Date = $Year."/".$Mon."/".$Day." ".$Hour.":".$Min.":".$Sec;

print "\$Mon :$Mon:\n" if ( $Verbose );
  $Mon=$Mon -1;
print "\$Mon :$Mon:\n" if ( $Verbose );
print "\$Date :$Date:\n" if ( $Verbose );

  $Time = timelocal($Sec,$Min,$Hour,$Day,$Mon,$Year);

  return( $Time );
 
}


sub ConvertReadableTimeStamp {
  my $TS=$_[0];
  my ( undef, $Mili )=split('\.', $TS);
  my $Time;


#  $Time = timelocal($Sec,$Min,$Hour,$Day,$Mon,$Year);
  $Time = strftime '%Y-%m-%d %H:%M:%S'.",".$Mili, localtime $TS;

  return( $Time );
 
}


sub ConvertATGTimeStamp {
  my $Line=$_[0];
  my $Time;

  $Line =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d,\d+) (.*)/;

  my $Year = $1;
  my $Mon = $2;
  my $Day = $3;
  my $Hour = $4;
  my $Min = $5;
  my $Sec = $6; 
  my $Data = $7;
 
 
  ( $Sec, $Mili )=split(',', $Sec);
  $Mili=substr("$Mili"."000000", 0, 6);

  my $Date = $Year."/".$Mon."/".$Day." ".$Hour.":".$Min.":".$Sec;

  $Mon=$Mon -1;

  $Time = timelocal($Sec,$Min,$Hour,$Day,$Mon,$Year).".".$Mili;

  return( "$Time $Data" );
 
}


sub ConvertATGSMTimeStamp {
  my $Line=$_[0];
  my $Time;

  return if ( ! $Line );
  $Line =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;

  # - 2015-04-02 15:34:26,37.68,-97.63,4443
  #print "\$Line :$Line:\n";

  my $Year = $1;
  my $Mon = $2;
  my $Day = $3;
  my $Hour = $4;
  my $Min = $5;
  my $Sec = $6; 
 
  $Mili="000000";

  my $Date = $Year."/".$Mon."/".$Day." ".$Hour.":".$Min.":".$Sec;

  $Mon=$Mon -1;
  $Time = timelocal($Sec,$Min,$Hour,$Day,$Mon,$Year).".".$Mili;

  return( $Time );
 
}


sub ConvertGPSTimeStamp {
  my $Line=$_[0];
  my $Time;

  $Line =~ /^\w+ (\w+) (\d\d+) (\d\d):(\d\d):(\d\d) UTC (\d\d\d\d)/;

  my $TMon = $1;
  my $Day = $2;
  my $Hour = $3;
  my $Min = $4;
  my $Sec = $5; 
  my $Year = $6;

  $Mon=$RMons{$TMon};
  
  my $Date = $Year."/".$Mon."/".$Day." ".$Hour.":".$Min.":".$Sec;

  $Mon=$Mon -1;

  $Time = timelocal($Sec,$Min,$Hour,$Day,$Mon,$Year);

  return( $Time );
 
}
