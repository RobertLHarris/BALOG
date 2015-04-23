#!/usr/bin/perl -w 
$| = 1;

use strict;
use diagnostics;
use Date::Calc qw(Add_Delta_YMD);
use Date::Manip;
use Date::Manip::Delta;
use Date::Manip::Date;
use Text::CSV_XS;
my $csv = Text::CSV_XS->new( { binary => 1 } );

chdir( "/opt/log/Accuroam" );

# NOTE:
#   log servers do not have perms to connect to Accuroam.  Need a MITM to transfer
#   scp fmcadm@10.240.81.12:/opt/accu/fmc/log/trans.log???? /opt/logs

# GoGo-One,  Corp plane
my $Challenger = "9034B2";

# Lets limit log processing for our construction
# Set to 0 for full run.
my $Loop;
my $Day=`/bin/date +%d`; chomp( $Day );
my $Mon=`/bin/date +%m`; chomp( $Mon );
my $Year=`/bin/date +%Y`; chomp( $Year );
my $Date=`/bin/date +%Y%m%d`; chomp( $Date );


# GetOpt
use vars qw( $opt_h $opt_v $opt_a $opt_A $opt_b $opt_c $opt_d $opt_D $opt_f $opt_F $opt_m $opt_p $opt_r $opt_R $opt_s $opt_S $opt_SA $opt_t $opt_T $opt_x $opt_X $opt_y $opt_w $opt_callinfo $opt_textinfo $opt_durinfo $opt_duration $opt_sipro );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v p=s a A=s b c=s d D f=s F=s m p=s r R s S=s SA t=s T x X y w duration durinfo callinfo textinfo sipro");

#Fix case issues.
if ( $opt_A ) {
  $opt_A =~ tr/a-z/A-Z/;
}


#
my $Verbose = 1 if ( $opt_v );  



# Declare Global Variables 
# Generic
my $date; my $time; 
my $year; my $mo; my $day;
my $MaxMODuration=0; my $MaxMTDuration=0; my $MaxMOAcid=""; my $MaxMTAcid="";
my @Activity;  my %Phones;
my %CallAcids; my %CallLegAcids; my %Rule_Reasons;
my %Calls; my %LogTimes; my %CallCode; my %CallEndedCode; my %Acids; my %SIPIDS; my %Callee; my $LoggingTime;
my %Texts;
my %Durations; my %CallBegin; my %CallEnd; my %CallAction; my %CallEndedAction; 
my %SIPCodes; my %Results; 
my %CallSIPCodes; my %CallResults; my %CallEndedSIPCodes; my %CallEndedResults;
my %Transaction;
my %ValidTails; 
my %ValidStart; 
my %ValidFinish; 
my %TestTails; my %TestTailNote;
my @Files; my $File; my @Loop;
# Do we need to keep phone trace activity?
my $Trace=0; $Trace=1 if ( $opt_p );
# Talk Specific
my %MOCalls; my %MTCalls; 
my $LogTime; my $CallStart; my $Action; my $SipCode; my $SIPID; my $PCAPID; my $ID; my $Callee; 
my $IntLeg_ID; my $CallBegin; my $CallEnd; my %CallDur; my $Duration;
my $Acid; my $Phone1; my %TotalAcids; my $Ratio; my $MOCallAttempts; my $BadMOCallAttempts; 
my $GoodMOCallAttempts; my $TransID; my %CallTrans; my $Content; my %Type;
my $MTCallAttempts; my $BadMTCallAttempts; my $GoodMTCallAttempts;
my $CallAttempts; my $BadCallAttempts; my $GoodCallAttempts;
my %BadMO; my %BadMT;
# SMS Specific
my %SMSAcids; my $TotalSent, my $TotalReceived;
my %MOSMS; my %MTSMS; my %SMSCode; my $Length; my %SMSMessage;
my $SMSAttempts; my $BadSMSAttempts; my $GoodSMSAttempts;
my $MOSMSAttempts; my $BadMOSMSAttempts; my $GoodMOSMSAttempts; 
my $MTSMSAttempts; my $BadMTSMSAttempts; my $GoodMTSMSAttempts;
my %BadMOSMS; my %BadMTSMS; my $Ret;
my %TXTLogTimes; my %TransID; my %TXTAction; my %TXTCallCode; my %TXTSIPIDS; my %TXTCallee; my %TXTContent; my %TXTID; my %TXTResult;
#
# Some flags we don't want to skip test acids because we are tracing a number
my $NoSkip=0; $NoSkip=1 if ( $opt_p );

#
# Define Variables 
#
my $TotalDur = 0;
my $MOCallDur = 0;
my $MTCallDur = 0;

#
# Lets define our error codes
# 2013/10/17 - Removed 0404 as a wet-ware issue
my @BadCodes=( "0403", "0408", "0409", "0410", "0482", "0500", "0503", "0504" );
#my %BadCodes = map {$_ => 1} @BadCodes;
# Ugly but it works for now
my %BadCodes;
$BadCodes{"0403"}=0; $BadCodes{"0408"}=0; 
$BadCodes{"0409"}=0; $BadCodes{"0410"}=0; $BadCodes{"0482"}=0;
$BadCodes{"0500"}=0; $BadCodes{"0503"}=0; $BadCodes{"0504"}=0;
# SMS Bad codes until we get specific bad SMS codes
my %BadSMSCodes=%BadCodes;
#
#
#

print "Defining Licensed Tails\n" if ( $Verbose );
&Define_Licensed_Tails;
#exit 0;
&DefineTestTails;

my $ShowCallDetails="F"; $ShowCallDetails = "T" if ( $opt_d );
my $ShowTextDetails="F"; $ShowTextDetails = "T" if ( $opt_m );


# Print out test tail info
if ( $opt_T ) {
  print "\n";
  print "Known Test Tails and Notes.\n";
  foreach my $loop ( sort ( keys ( %TestTails ))) {
   print "  $loop";
    print "  :  $TestTailNote{$loop}" if ( $TestTailNote{$loop} );
    print "\n";
  }
  exit 0;
}

# We want to run on yesterday's logs
if ( $opt_y ) {
  my $Yesterday=ParseDate( "yesterday" );
  $Yesterday=substr( $Yesterday, 0, 8 );
  $opt_F=$Yesterday;
}
# #We want to run on the last X days logs


my $startDate = '2000-01-01';
my ($startYear, $startMonth, $startDay) = $startDate =~ m/(\d{4}-(\d{2})-\d{2})/;

# Lets get any input date in the right format
if ( $opt_F ) {
  $opt_F =~ s/-//g;
}

if ( $opt_c ) {
  my $Yesterday;
  # Get actual yesterday first, easier that way
  if ( $opt_F ) {
    $Yesterday=ParseDate( "$opt_F" );
  } else {
    $Yesterday=ParseDate( "yesterday" );
  }
  $Yesterday=substr( $Yesterday, 0, 8 );
  $opt_F=$Yesterday;

  my $Count=$opt_c;
  foreach $Loop ( 2..$Count ) {
    print "\$Loop :$Loop:\n" if ( $opt_v); 
    ( $year, $mo, $day ) = $Yesterday =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
    # Subtract 1 day
    ( $year, $mo, $day ) = Add_Delta_YMD($year, $mo, $day, 0, 0, -1);
    $mo=substr("0"."$mo", -2);
    $day=substr("0"."$day", -2);
    my $NewDay = $year.$mo.$day;
    $Yesterday=substr( $NewDay, 0, 8 );
    $opt_F=$opt_F.",".$Yesterday;
  }
  print "Running the report for the dates: $opt_F\n";
}


# We want to run on the weekend's logs
 if ( $opt_w ) {
   my $Sunday;
   $Sunday=ParseDate( "last Sunday");  
   $Sunday=substr( $Sunday, 0, 8 );


    ( $year, $mo, $day ) = $Sunday =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
   # Find the previous Friday 
    my $Friday;
    $Friday=ParseDate( "last Friday");
    $Friday=substr( $Friday, 0, 8 );
    my $Saturday=ParseDate( "last Saturday");
    $Saturday=substr( $Saturday, 0, 8 );
#    $opt_F=$Friday.",".$Sunday;
  $opt_F="$Friday,$Saturday,$Sunday";

  print "Running the report for the dates: $opt_F\n";
  }

if (( $opt_h ) || ( ! ( $opt_f || $opt_F ) ))  {
  print "\n\n";   
  print "Usage:  AccuLogs.pl <options> -f <Log_File>\n";   
  print " -h = help (This screen)\n";   
  print "\n";
  print "Required: \n";
  print " -f <Log_File> : Specify a selection of files to read.\n";   
  print " -F <Log_File_Date> : Specify a base date log file (i.e. 20131125, wanting all with that pattern)\n";
  print " -y : Use yesterday's log files.\n";
  print " -w : Use the weekend's log files.\n";
  print " -B ** Deprecated, just use -F for the base.\n";
  print " -c X : Use the last X days' log files.\n";
  print "\n";
  print "Output Format: \n";
  print " -R = Generate GGTT Standard Report\n";
  print " -S <N>\n";
  print "     1 = Generate GGTT csv stats report\n";
  print "     2 = Generate GGTT minimal csv stats report\n";
  print "--SA = Generate SA report\n";
  print " -D = Dump all ACIDs found in the file\n";
  print "--duration = Dump the duration of all calls found\n";
  print "--durinfo  = Dump the duration information report\n";
  print "--callinfo = Dump the information for calls\n";
  print "--textinfo = Dump the information for texts\n";
  print "--sipro = List the number of sipro licenses used\n";
  print "\n";
  print "Options: \n";
  print " -A <Acid> = Show activity for a specific Acid\n";
  print "             If the challenger ( $Challenger ) is specified, it implies -x\n";
  print " -t <TransID> = Show activity for a specific transaction ID\n";
  print " ** -r = Show Raw Transaction Log, no translation\n";
  print " -a = Show Acid activity\n";
  print " -b = Show Test (Bad) tails\n";
  print " -x = Show Normally excluded non-test tails Details\n";   
  print " -X = Show Normally excluded Challenger-test tails Details ONLY\n";   
  print " -s = Show Spoof activity\n";
  print " -d = Show Talk Details\n";   
  print " -p <PhoneNumber> = Show Phone Activity\n";   
  print " -m = Show Text Message Details\n";   
  print " -T = Show Defined Test Tails\n";   
  print " -v = Verbose output\n";   
  print " -l <level>\n";   
  print "    0 = All, 1 = Crit only, 2 = Heartbeat only\n";   
  print "\n\n\n";   
  exit 0; 
}


# Lets read in our Data
if ( $opt_f ) {
  open(INPUT, "cat $opt_f |" );
} 
if ( $opt_F ) {
  print "\$opt_F :$opt_F:\n" if ( $opt_v );
  my $DatePattern=$opt_F;
  if ( $DatePattern =~ /,/ ) {
    my (@Dates)=split(',', $DatePattern);
    foreach $Loop ( @Dates ) {
      print "\$Loop :$Loop:\n" if ( $opt_v );
      push( @Files, `ls -1 trans.log.$Loop* 2>/dev/null` ); 
      if ( $Loop =~ /$Date/ ) {
        push(@Files, 'trans.log');
      }
    } 
  } else {
    @Files=`ls -1 trans.log.$DatePattern* 2>/dev/null`; chomp( @Files );
    if ( $Date =~ /$DatePattern/ ) {
      push(@Files, 'trans.log');
    }
  }
  chomp( @Files );

  print "\@Files :@Files:\n" if ( $opt_v );
  if ( ! $Files[0] ) {
    print "\n";
    print "No source files found.\n";
    print "\n";
    exit 0;
  } else {
    open(INPUT, "cat @Files |" );
  }
}

while(<INPUT>) {
  chomp;
 
  next if ( /closing  file/ );

  if ( $opt_A ) {
    next unless ( /$opt_A/ );
  }
  &ProcessLines;
  $Loop++;
}

print "\$opt_p :$opt_p:\n" if ( ( $Verbose ) && ( $opt_p ) );
&TracePhone if ( $opt_p );  
&ShowTransactions if ( $opt_t );  
&ShowDurInfo if ( $opt_durinfo );  
&ShowCallInfo if ( $opt_callinfo );  
&ShowTextInfo if ( $opt_textinfo );  
&ShowSummary; 
&ShowSiPro if ( $opt_sipro );
exit 0;



########################
# Sub-Procs Below Here #
########################
sub ProcessLines {
  #Lets remove non-BA entries

  $_ =~ s/[^[:print:]]//g;

  # Lets return if we are searching on a specific phone number
  if ( $opt_p ) {
    if ( $_ !~ /$opt_p/ ) {
      print "\$_ :$_:\n" if ( $Verbose );
      print "$opt_p not found, next line.\n" if ( $Verbose );
      return;
    }
  }

  &ProcessSsInviteReceivedUas if ( /,SsInviteReceivedUas,/ );
  &ProcessCheckCalls if ( /,CheckCalls,/ );
  &ProcessReadSubscriber if ( /,ReadSubscriber,/ );
  &ProcessSsInviteSentUac if ( /,SsInviteSentUac,/ );
  &ProcessSsInviteLeg1_Rsp if ( /,SsInviteLeg1_Rsp,/ );
  &ProcessSsInviteLeg2Rsp if ( /,SsInviteLeg2Rsp,/ );
  &ProcessMOCall if ( /,SipCall,/ );
  &ProcessMOCallEnded if ( /,SipCallEnded,/ );
  &ProcessMTCall if ( /,SipMtCall,/ );
  &ProcessMTCallEnded if ( /,SipMtCallEnded,/ );

  &ProcessSipMsg if ( /,SipMessage,/ );
  &ProcessSipMtMsg if ( /,MapMtShortMessage,/);
#  &ProcessSsMessageSent if ( /,SsMessageSent,/ );
#  &ProcessSsMessageReceived if ( /,SsMessageReceived,/);
}

sub Check_Acids {

  # Value of Zero = good.
  # Value of One = invalid

  my $Ret=1;
  # $Ret=0 if ( $ValidTails{$Acid} );

  # Unknown acid
  if ( ! $ValidTails{$Acid} ) {
    return($Ret);
  }

  # Not a valid Acid
  if ( $_ !~ /[0-9a-fA-F]{6}/) {
    return($Ret);
  }


  my ( $Date, $Time )=split ( "\-", $LoggingTime );
  my ( $Day, $Mon, $Year )=split( ":", $Date );
  $LoggingTime=$Year.$Mon.$Day.$Time;
  $LoggingTime =~ s/[ |\-|:|\.]//g;

  return($Ret) if ( $Acid eq "FFFFFF" );

  if ( $ValidTails{$Acid} ) {
    $Ret=0if (( $LoggingTime > $ValidStart{$Acid} ) && ( $LoggingTime < $ValidFinish{$Acid} ));
  }

  print "\$Acid :$Acid:\n" if ( $Verbose );
  print "\$LoggingTime         :$LoggingTime:\n" if ( $Verbose );
  print "\$ValidStart{$Acid}  :$ValidStart{$Acid}:\n" if ( $Verbose );
  print "\$ValidFinish{$Acid} :$ValidFinish{$Acid}:\n" if ( $Verbose );
 
  return($Ret);
}


sub Define_Licensed_Tails {
  #Tails known good, list generated by Jack
  my $Tail; my $Start; my $Finish;

  #print  "echo \"select distinct acid, effective_start_date, effective_end_date from [TARGET_REPORTING].[dbo].[DIM_LICENSE_KEYS] l where l.item_nbr = 'P16637-101' and l.aircraft_reg_nbr <> 'NTSLAB'\" | isql -q GGTTPROD NETOPS_USR_RO GXk91mc15Tz \n" if ( $Verbose );
  print  "echo \"select distinct acid, effective_start_date, effective_end_date from [TARGET_REPORTING].[dbo].[DIM_LICENSE_KEYS] l where l.item_nbr = 'P16637-101' and l.aircraft_reg_nbr <> 'NTSLAB'\" | isql -q GGTTPROD NETOPS_USR_RO Up5!w0N# \n" if ( $Verbose );
  open(INPUT, "echo \"select distinct acid, effective_start_date, effective_end_date from [TARGET_REPORTING].[dbo].[DIM_LICENSE_KEYS] l where l.item_nbr = 'P16637-101' and l.aircraft_reg_nbr <> 'NTSLAB'\" | isql -q GGTTPROD NETOPS_USR_RO Up5!w0N# |");
  while(<INPUT>) {
    chomp;
    print "\$_ :$_:\n" if ( $Verbose );
    next if ( $_ =~ /^$/ );
    next if ( $_ !~ /\| +[0-9a-zA-Z]{6} +.*/);

    print "License Info :$_:\n" if ( $Verbose );

  
    $_ =~ /\| (\w+) *\| (\d\d\d\d\-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d)\| (\d\d\d\d\-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d\d)\|/;
  
    my $Tail=$1;
    # Fix Case issue
    $Tail =~ tr/a-z/A-Z/;


    next if ( $Tail =~ /^$/ );

    if ( ! $Tail ) {
      print "No matches in License check.\n";
      print "\$_ : $_\n";
    }


    my $Start=$2;
    my $Finish=$3;
    $Tail =~ s/\W//g;
    $Start =~ s/\.\d+//g;
    $Start =~ s/[ |\-|:|\.]//g;
    $Finish =~ s/\.\d+//g;
    $Finish =~ s/[ |\-|:|\.]//g;
    $ValidTails{"$Tail"}=1; 
    #
    # This is to deal with multiple licenses on one tail:
    # 904484  2014-06-20 00:00:00.000 2014-06-23 23:59:59.000
    # 904484  2014-06-24 00:00:00.000 9999-12-31 00:00:00.000
    #
    if ( $ValidStart{"$Tail"} ) {
      if ( $Start < $ValidStart{"$Tail"} ) {
        $ValidStart{"$Tail"}=$Start;
      }
    } else {
      $ValidStart{"$Tail"}=$Start; 
    }
    if ( $ValidFinish{"$Tail"} ) {
      if ( $Finish > $ValidFinish{"$Tail"} ) {
        $ValidFinish{"$Tail"}=$Finish;
      }
    } else {
      $ValidFinish{"$Tail"}=$Finish; 
    }
    print "\$Tail :$Tail:\n" if ( $Verbose );
    print "\$Start :$Start:\n" if ( $Verbose );
    print "\$Finish :$Finish:\n" if ( $Verbose );
  }
  close(INPUT);

  # Force this for NetJets for now
  $ValidTails{"905D13"}=1;
  $ValidStart{"905D13"}=20140101180247;
  $ValidFinish{"905D13"}=20150101180247;
}


sub DefineTestTails {
  if ( ! $opt_s ) {
    # Developmental Spoof tail.  Should not be seen in the wild.
    $TestTails{"1234567"}=1; $TestTailNote{"1234567"}="Dev Spoof Acid";
    $TestTails{"7654321"}=1; $TestTailNote{"7654321"}="Dev Spoof Acid";
    $TestTails{"123456"}=1; $TestTailNote{"7654321"}="Dev Spoof Acid";
  } else {
    $NoSkip=1;
  }
  if ( ! $opt_b ) {
    #
    # Generic Test Tails
    $TestTails{"902AF0"}=1; $TestTails{"A70BD4"}=1; $TestTails{"A8079D"}=1; $TestTails{"C0CAF2"}=1;
    $TestTails{"D608DD"}=1; $TestTails{"D64197"}=1; $TestTails{"D641F3"}=1; $TestTails{"DB40D8"}=1;
    $TestTails{"DB4188"}=1; $TestTails{"DB418E"}=1; $TestTails{"A70624"}=1; $TestTails{"A70667"}=1;
    $TestTails{"D609B2"}=1; $TestTails{"D608F3"}=1; $TestTails{"C245B4"}=1; $TestTails{"C09BAA"}=1;
    $TestTails{"C09B85"}=1; $TestTails{"C092B6"}=1; $TestTails{"C092AB"}=1; $TestTails{"C0181C"}=1;
    $TestTails{"BACA12"}=1; $TestTails{"BACA12"}=1; $TestTails{"BACA08"}=1; $TestTails{"BACA06"}=1;
    $TestTails{"BACA05"}=1; $TestTails{"BACA04"}=1; $TestTails{"BACA03"}=1; $TestTails{"BACA02"}=1;
    $TestTails{"BACA01"}=1; $TestTails{"BABB89"}=1; $TestTails{"AABE3B"}=1; $TestTails{"A706C3"}=1;
    $TestTails{"A7089C"}=1; $TestTails{"A7089D"}=1; $TestTails{"A70AC2"}=1; $TestTails{"902BA6"}=1;
    $TestTails{"902B9D"}=1; $TestTails{"902B2F"}=1; $TestTails{"902AEC"}=1; $TestTails{"902AEC"}=1;
    $TestTails{"902316"}=1; 
    $TestTails{"A70BCB"}=1; 
    $TestTails{"AAFEE9"}=1; 
    $TestTails{"C091CB"}=1; 
    $TestTails{"C09334"}=1; $TestTailNote{"C09334"}="TechSupport ATG";
    $TestTails{"902B1D"}=1; $TestTailNote{"902B1D"}="Pizza ( Engr Testing )";
    $TestTails{"A7066D"}=1; $TestTailNote{"A7066D"}="Itasca BA Testing";
    $TestTails{"BACA80"}=1; $TestTailNote{"BACA80"}="ST4300 Test";
    $TestTails{"BACA90"}=1; $TestTailNote{"BACA90"}="BA Healthcheck ATG";
    $TestTails{"BACA98"}=1; $TestTailNote{"BACA98"}="Unknown Test";
    $TestTails{"10496"}=1; $TestTailNote{"10496"}="Uknown AircellTest";
    $TestTails{"11021"}=1; $TestTailNote{"11021"}="Uknown AircellTest";
    $TestTails{"11224"}=1; $TestTailNote{"11224"}="Uknown AircellTest";
    $TestTails{"11225"}=1; $TestTailNote{"11225"}="Uknown AircellTest";
    $TestTails{"FFFFFF"}=1; $TestTailNote{"FFFFFF"}="Test";
    # CA
    $TestTails{"TSS1"}=1; $TestTailNote{"TSS1"}="Glantsman/ORS test acid";
    $TestTails{"TSS1AAL"}=1; $TestTailNote{"TSS1AAL"}="Glantsman/ORS test acid";
    # Need Confirmation
    $TestTails{"WLT1"}=1; $TestTailNote{"WLT1"}="Need owner confirmation";
    $TestTails{"LT2"}=1; $TestTailNote{"LT2"}="Need owner confirmation";
    $TestTails{"N74JA"}=1; $TestTailNote{"N74JA"}="Need owner confirmation";
    $TestTails{"CATESTAAL"}=1; $TestTailNote{"CATESAAL"}="Need owner confirmation";
    $TestTails{"ithc4"}=1; $TestTailNote{"ithc4"}="Need owner confirmation";
    $TestTails{"N723TW"}=1; $TestTailNote{"N723TW"}="Need owner confirmation";
    $TestTails{"N955U"}=1; $TestTailNote{"N955U"}="Need owner confirmation";
    $TestTails{"N9677W"}=1; $TestTailNote{"N9677W"}="Need owner confirmation";

    # Customer Test Tails
  } else {
    $NoSkip=1;
  }

  # If we specify the challenger as the one we care about, don't mark it to be ignored
  $opt_x = 1 if ( ( $opt_A ) && ( $opt_A eq $Challenger ));
  if ( ( ! $opt_x ) && ( ! $opt_X) ) {
    $TestTails{$Challenger}=1; $TestTailNote{$Challenger}="Challenger (GoGo One!)";
  } 
}

sub ProcessSipMsg {
  print "\n\n\n" if ( $Verbose );
  print "SipMsg :$_:\n" if ( $Verbose );
  # Lets clear out some garbage

  my @Tmp=split(',', $_);
  return if ( $#Tmp < 21 );

  $csv->parse($_) or die "Error processing $_".$csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, undef, $Callee, $Content, undef, undef, $ID, undef, undef, undef, undef, undef, $Result) = $csv->fields();
  #print "undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, undef, $Callee, $Content, undef, undef, $ID, undef, undef, undef, undef, undef, $Result \n";


  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  print "\n" if ( $Verbose );
  print "\$ID :$ID:\n" if ( $Verbose );

  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

#  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  $SMSAcids{$Acid}=0 if ( ! $SMSAcids{$Acid} );
  $SMSAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  $SMSMessage{$SIPID}="" if ( ! $SMSMessage{$SIPID} );
  $SMSMessage{$SIPID}=$SMSMessage{$SIPID}."\n"."$Callee : $Content";

  #Lets get some info for stats
  $Texts{$TransID}=1;
  $TXTLogTimes{$TransID}=$LogTime;
  $TXTAction{$TransID}=$Action;
  $TXTCallCode{$TransID}=$SipCode;
  $TXTSIPIDS{$TransID}=$SIPID;
  $TXTCallee{$TransID}=$Callee;
  $TXTContent{$TransID}=$Content;
  $TXTID{$TransID}=$Acid;
  $TXTResult{$TransID}=$Result;

  print "\$SMSAcids{$Acid} :$SMSAcids{$Acid}:\n" if ( $Verbose );

  push( @Activity, "$LogTime : $SIPID sent $Callee a message : $Content ( Result = $SipCode )" );

  # What about MO SMS success rate?
  $MOSMSAttempts++;
  if ( defined $BadSMSCodes{$SipCode} ) {
    $BadMOSMSAttempts++;
    $BadMOSMS{$SipCode}++;
    $BadSMSCodes{$SipCode}++;
  } else {
    $GoodMOSMSAttempts++;
  }
}


sub ProcessSsMessageSent {
  print "\n\n\n" if ( $Verbose );
  print "SsMsgSent :$_:\n" if ( $Verbose );
  # Lets clear out some garbage

  $csv->parse($_) or die $csv->error_diag();
  #my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, undef, $Callee, $Content, undef, undef, $ID, undef, undef, undef, undef, undef, $Result) = $csv->fields();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, undef, $SIPID, undef, $Callee, undef, undef, $Content, $ID, undef, undef, $Result) = $csv->fields();

  return if ( ! $ID );
  return if ( $ID !~ /acid/ );
  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  print "\n" if ( $Verbose );
  print "\$ID :$ID:\n" if ( $Verbose );

  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

#  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  $SMSAcids{$Acid}=0 if ( ! $SMSAcids{$Acid} );
  $SMSAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  $SMSMessage{$SIPID}="" if ( ! $SMSMessage{$SIPID} );
  $SMSMessage{$SIPID}=$SMSMessage{$SIPID}."\n"."$Callee : $Content";

  #Lets get some info for stats
  $Texts{$TransID}=1;
  $TXTLogTimes{$TransID}=$LogTime;
  $TXTAction{$TransID}=$Action;
  $TXTCallCode{$TransID}=$SipCode;
  $TXTSIPIDS{$TransID}=$SIPID;
  $TXTCallee{$TransID}=$Callee;
  $TXTContent{$TransID}=$Content;
  $TXTID{$TransID}=$Acid;
  $TXTResult{$TransID}=$Result;

  print "\$SMSAcids{$Acid} :$SMSAcids{$Acid}:\n" if ( $Verbose );

  push( @Activity, "$LogTime : $SIPID sent $Callee a message : $Content ( Result = $SipCode )" );

  # What about MO SMS success rate?
  $MOSMSAttempts++;
  if ( defined $BadSMSCodes{$SipCode} ) {
    $BadMOSMSAttempts++;
    $BadMOSMS{$SipCode}++;
    $BadSMSCodes{$SipCode}++;
  } else {
    $GoodMOSMSAttempts++;
  }
}


sub ProcessSipuRegister {
  print "\n\n\n" if ( $Verbose );
  print "SipuRegister :$_:\n" if ( $Verbose );
  # Lets clear out some garbage

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, $Length, $Content, undef, undef, undef, $ID, undef, undef, undef, undef, undef, undef, undef, undef, undef, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  print "\n" if ( $Verbose );
  print "\$ID :$ID:\n" if ( $Verbose );
 
  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  $SMSAcids{$Acid}=0 if ( ! $SMSAcids{$Acid} );
  $SMSAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  print "\$SMSAcids{$Acid} :$SMSAcids{$Acid}:\n" if ( $Verbose );

  push( @Activity, "$LogTime : $SIPID received a message from $Callee : $Content ( Result = $SipCode, Duration = $Duration )");

  # What about MO SMS success rate?
  $MTSMSAttempts++;
  if ( defined $BadSMSCodes{$SipCode} ) {
    $BadMTSMSAttempts++;
    $BadMTSMS{$SipCode}++;
    $BadSMSCodes{$SipCode}++;
  } else {
    $GoodMTSMSAttempts++;
  }
}


sub ProcessSipMtMsg {
  print "\n\n\n" if ( $Verbose );
  print "SipMtMsg :$_:\n" if ( $Verbose );
  # Lets clear out some garbage

  my @Tmp=split(',', $_);
  return if ( $#Tmp < 21 );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, $Length, $Content, undef, undef, undef, $ID, undef, undef, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  print "\n" if ( $Verbose );
  print "\$ID :$ID:\n" if ( $Verbose );
 
  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  $SMSAcids{$Acid}=0 if ( ! $SMSAcids{$Acid} );
  $SMSAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  #Lets get some info for stats
  $Texts{$TransID}=1;
  $TXTLogTimes{$TransID}=$LogTime;
  $TXTAction{$TransID}=$Action;
  $TXTCallCode{$TransID}=$SipCode;
  $TXTSIPIDS{$TransID}=$SIPID;
  $TXTCallee{$TransID}=$Callee;
  $TXTContent{$TransID}=$Content;
  $TXTID{$TransID}=$Acid;
  $TXTResult{$TransID}=$Result;

  print "\$SMSAcids{$Acid} :$SMSAcids{$Acid}:\n" if ( $Verbose );

  push(@Activity, "$LogTime : $SIPID received a message from $Callee : $Content ( Result = $SipCode )");

  # What about MO SMS success rate?
  $MTSMSAttempts++;
  if ( defined $BadSMSCodes{$SipCode} ) {
    $BadMTSMSAttempts++;
    $BadMTSMS{$SipCode}++;
    $BadSMSCodes{$SipCode}++;
  } else {
    $GoodMTSMSAttempts++;
  }
}


sub ProcessSsMessageReceived {
  print "\n\n\n" if ( $Verbose );
  print "SsMsgRec :$_:\n" if ( $Verbose );
  # Lets clear out some garbage

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, undef, $Length, $Content, $ID, undef, undef, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  print "\n" if ( $Verbose );
  print "\$ID :$ID:\n" if ( $Verbose );
 
  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  $SMSAcids{$Acid}=0 if ( ! $SMSAcids{$Acid} );
  $SMSAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  #Lets get some info for stats
  $Texts{$TransID}=1;
  $TXTLogTimes{$TransID}=$LogTime;
  $TXTAction{$TransID}=$Action;
  $TXTCallCode{$TransID}=$SipCode;
  $TXTSIPIDS{$TransID}=$SIPID;
  $TXTCallee{$TransID}=$Callee;
  $TXTContent{$TransID}=$Content;
  $TXTID{$TransID}=$Acid;
  $TXTResult{$TransID}=$Result;

  print "\$SMSAcids{$Acid} :$SMSAcids{$Acid}:\n" if ( $Verbose );

  push(@Activity, "$LogTime : $SIPID received a message from $Callee : $Content ( Result = $SipCode )");

  # What about MO SMS success rate?
  $MTSMSAttempts++;
  if ( defined $BadSMSCodes{$SipCode} ) {
    $BadMTSMSAttempts++;
    $BadMTSMS{$SipCode}++;
    $BadSMSCodes{$SipCode}++;
  } else {
    $GoodMTSMSAttempts++;
  }
}


sub ProcessMOCall {
  print "\n\n\n" if ( $Verbose );
  print "MOCall :$_:\n" if ( $Verbose );

  # Lets clear out some garbage
  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, $TRN, $IN_Route, $IntLeg_ID, $Leg1_Reason, $ExtLeg_ID, $ExtLeg_Reason, undef, undef, $ID, undef, undef, undef, undef, undef, undef, $Rule_Reason, $Leg3_ID, $Leg3_Reason, $Result) = $csv->fields();
  print "\n" if ( $Verbose );

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }
print "Continuing\n" if ( $_ =~ /1644575/ );

  if ( $ShowCallDetails eq "T" ) {
    print "LogTime : $LogTime\n";
    print "Action : $Action\n";
    print "TransID : $TransID\n";
    print "SipCode : $SipCode\n";
    print "SIPID : $SIPID\n";
    print "Callee : $Callee\n";
    print "IntLeg_ID : $IntLeg_ID\n";
    print "Acid : $Acid\n";
    print "\n";
  }


  $CallAcids{$Acid}=0 if ( ! $CallAcids{$Acid} );
  $CallAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  #Lets get some info for stats
  $Calls{$IntLeg_ID}=1;
  $CallTrans{$IntLeg_ID}=$TransID;
  $LogTimes{$IntLeg_ID}=$LogTime;
  $CallCode{$IntLeg_ID}=$SipCode;
  $SIPIDS{$IntLeg_ID}=$SIPID;
  $Callee{$IntLeg_ID}=$Callee;
  $Phones{$SIPID}=1;
  $CallLegAcids{$IntLeg_ID}=$Acid;
  $Acids{$IntLeg_ID}=$Acid;
  $Rule_Reasons{$IntLeg_ID}=$Rule_Reason;
  $CallAction{$IntLeg_ID}=$Action;
  $CallSIPCodes{$IntLeg_ID}=$SipCode;
  $CallResults{$IntLeg_ID}=$Result;
  if ( $CallResults{$IntLeg_ID} eq "SipError" ) {
    $CallEndedCode{$IntLeg_ID}="SipError";
    $Durations{$IntLeg_ID}="SipError";
    $CallBegin{$IntLeg_ID}="SipError";
    $CallEnd{$IntLeg_ID}="SipError";
    $CallEndedSIPCodes{$IntLeg_ID}="SipError";
    $CallEndedAction{$IntLeg_ID}="SipError";
    $CallEndedResults{$IntLeg_ID}="SipError";
  }

  push(@Activity, "$LogTime : $SIPID called to $Callee ( Result = $SipCode )");

  # What about MO call success rate?
  if ( $Action eq "SipCall" ) {
    $MOCallAttempts++;
    if (defined $BadCodes{$SipCode}) {
      $BadMOCallAttempts++;
      $BadMO{$SipCode}++;
    } else {
      $GoodMOCallAttempts++;
    }
  }
}


sub ProcessMOCallEnded {
  # Lets clear out some garbage
  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, $IntLeg_ID, $Leg1_Reason, $ExtLeg_ID, $ExtLeg_Reason, $CallBegin, $CallEnd,$Duration, $TRN, $ID, undef, undef, undef, undef, undef, $Leg3_ID, $Leg3_Reason, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  if ( $MaxMODuration < $Duration ) {
    $MaxMODuration= $Duration;
    $MaxMOAcid=$Acid;
  }

  if ( $ShowCallDetails eq "T" ) {
    print "LogTime : $LogTime\n";
    print "Action : $Action\n";
    print "SipCode : $SipCode\n";
    print "SIPID : $SIPID\n";
    print "Callee : $Callee\n";
    print "IntLeg_ID : $IntLeg_ID\n";
    print "CallBegin : $CallBegin:\n";
    print "CallEnd : $CallEnd:\n";
    print "Duration : $Duration:\n";
    print "Acid : $Acid\n";
    print "Result : $Result\n";
    print "\n";
  }

  if ( $opt_duration) {
    my $Range;
    $Range="0" if ( $Duration == 0 );
    $Range="1" if (( $Duration > 0 ) && ( $Duration < 16 ));
    $Range="2" if (( $Duration > 15 ) && ( $Duration < 31 ));
    $Range="3" if (( $Duration > 30 ) && ( $Duration < 61 ));
    $Range="4" if (( $Duration > 60 ) && ( $Duration < 181 ));
    $Range="5" if (( $Duration > 180 ) && ( $Duration < 301 ));
    $Range="7" if ( $Duration > 300 );
    $Range="NC" if ( $Result eq "CallNotConnected" );

    print "LogTime, Action, SipCode, SIPID, Callee, IntLeg_ID, CallBegin, CallEnd, Duration, Acid, Result, Range\n";
    print "$LogTime, $Action, $SipCode, $SIPID, $Callee, $IntLeg_ID, $CallBegin, $CallEnd, $Duration, $Acid, $Result, $Range\n";
  }

  #Lets get some info for stats
  $Calls{$IntLeg_ID}=1;
  $LogTimes{$IntLeg_ID}=$LogTime;
  $CallTrans{$IntLeg_ID}=$TransID;
  $CallEndedCode{$IntLeg_ID}=$SipCode;
  $SIPIDS{$IntLeg_ID}=$SIPID;
  $Callee{$IntLeg_ID}=$Callee;
  $Phones{$SIPID}=1;
  $CallLegAcids{$IntLeg_ID}=$Acid;
  $Acids{$IntLeg_ID}=$Acid;
  $Durations{$IntLeg_ID}=$Duration;
  $CallBegin{$IntLeg_ID}=$CallBegin;
  $CallEnd{$IntLeg_ID}=$CallEnd;
  $CallEndedSIPCodes{$IntLeg_ID}=$SipCode;
  $CallEndedAction{$IntLeg_ID}=$Action;
  $CallEndedResults{$IntLeg_ID}=$Result;


  push( @Activity, "$LogTime : $SIPID ended the call to $Callee ( Result = $SipCode, Duration = $Duration )" );

  $Type{$IntLeg_ID} = "SipMO";
  if ( ! $CallDur{$IntLeg_ID} ) {
    $CallDur{$IntLeg_ID} = $Duration;
  } else {
    $CallDur{$IntLeg_ID} = $CallDur{$IntLeg_ID} + $Duration;
  }
  $MOCallDur = $MOCallDur + $Duration;
  $TotalDur = $TotalDur + $Duration;
}


sub ProcessMTCall {
  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $SIPID, $Callee, $TRN, $IN_Route, $ExtLeg_ID, $ExtLeg_Reason, $IntLeg_ID, $IntLeg_Reason, undef, undef, undef, undef, undef, $ID, undef, undef,undef, $Rule_Reason, $Leg3_ID, $Leg3_Reason, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  $Acid=$1; $Phone1=$2;
  # $Acid="$SIPID" if ( ! $Acid );
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;


  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  if ( $ShowCallDetails eq "T" ) {
    print "LogTime : $LogTime\n";
    print "Action : $Action\n";
    print "SipCode : $SipCode\n";
    print "SIPID : $SIPID\n";
    print "Callee : $Callee\n";
    print "IntLeg_ID : $IntLeg_ID\n";
    print "Acid : $Acid\n";
    print "\n";
  }


  $CallAcids{$Acid}=0 if ( ! $CallAcids{$Acid} );
  $CallAcids{$Acid}++;
  $TotalAcids{$Acid}=0 if ( ! $TotalAcids{$Acid} );
  $TotalAcids{$Acid}++;

  #Lets get some info for stats
  $Calls{$IntLeg_ID}=1;
  $LogTimes{$IntLeg_ID}=$LogTime;
  $CallTrans{$IntLeg_ID}=$TransID;
  $CallCode{$IntLeg_ID}=$SipCode;
  $SIPIDS{$IntLeg_ID}=$SIPID;
  $Callee{$IntLeg_ID}=$Callee;
  $Phones{$SIPID}=1;
  $CallLegAcids{$IntLeg_ID}=$Acid;
  $Acids{$IntLeg_ID}=$Acid;
  $Rule_Reasons{$IntLeg_ID}=$Rule_Reason;
  $CallSIPCodes{$IntLeg_ID}=$SipCode;
  $CallAction{$IntLeg_ID}=$Action;
  $CallResults{$IntLeg_ID}=$Result;

  push( @Activity, "$LogTime : $SIPID received a call from  $Callee ( Result = $SipCode )" );

  # What about MT call success rate?
  if ( $Action eq "SipMtCall" ) {
    $MTCallAttempts++;
    if (defined $BadCodes{$SipCode}) {
      $BadMTCallAttempts++;
      $BadMT{$SipCode}++;
    } else {
      $GoodMTCallAttempts++;
    }
  }
}

sub ProcessMTCallEnded {
  print "MTCallEnd :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $Callee, $SIPID, $ExtLeg_ID, $ExtLeg_Reason, $IntLeg_ID, $IntLeg_Reason, $CallBegin, $CallEnd, $Duration, $TRN, undef, undef, undef, $ID, undef, undef, $Leg3_ID, $Leg3_Reason, $Result) = $csv->fields();
  $PCAPID=$ExtLeg_ID;

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

  $ID =~ /<acid>(.*)<\/acid><msisdn>(.*)<\/msisdn>/;
  # $Acid="$SIPID" if ( ! $Acid );
  $Acid=$1; $Phone1=$2;
  return if ( ! $Acid );
  $Acid =~ tr/a-z/A-Z/;

  # Lets blow out CA Acids
  return if ( $Acid !~ /[0-9A-F]{6}/ );

  $LoggingTime=$LogTime;

  # We don't want to skip any Acids when searching a specific ID
  if ( $NoSkip == 0 ) {
    $Ret=&Check_Acids;
    return if ( $Ret );
  }

  if ( $ShowCallDetails eq "T" ) {
    print "LogTime : $LogTime\n";
    print "Action : $Action\n";
    print "SipCode : $SipCode\n";
    print "SIPID : $SIPID\n";
    print "Callee : $Callee\n";
    print "IntLeg_ID : $IntLeg_ID\n";
    print "CallBegin : $CallBegin:\n";
    print "CallEnd : $CallEnd:\n";
    print "Duration : $Duration:\n";
    print "Acid : $Acid\n";
    print "Result : $Result\n";
    print "\n";
  }

  if ( $MaxMTDuration < $Duration ) {
    $MaxMTDuration= $Duration;
    $MaxMTAcid=$Acid;
  }


  if ( $opt_duration) {
    my $Range;
    $Range="0" if ( $Duration == 0 );
    $Range="1" if (( $Duration > 0 ) && ( $Duration < 16 ));
    $Range="2" if (( $Duration > 15 ) && ( $Duration < 31 ));
    $Range="3" if (( $Duration > 30 ) && ( $Duration < 61 ));
    $Range="4" if (( $Duration > 60 ) && ( $Duration < 181 ));
    $Range="5" if (( $Duration > 180 ) && ( $Duration < 301 ));
    $Range="7" if ( $Duration > 300 );
    $Range="NC" if ( $Result eq "CallNotConnected" );

    print "LogTime, Action, SipCode, SIPID, Callee, IntLeg_ID, CallBegin, CallEnd, Duration, Acid, Result, Range\n";
    print "$LogTime, $Action, $SipCode, $SIPID, $Callee, $IntLeg_ID, $CallBegin, $CallEnd, $Duration, $Acid, $Result, $Range\n";
  }

  #Lets get some info for stats
  $Calls{$IntLeg_ID}=1;
  $LogTimes{$IntLeg_ID}=$LogTime;
  $CallTrans{$IntLeg_ID}=$TransID;
  $CallEndedCode{$IntLeg_ID}=$SipCode;
  $SIPIDS{$IntLeg_ID}=$SIPID;
  $Callee{$IntLeg_ID}=$Callee;
  $Phones{$SIPID}=1;
  $CallLegAcids{$IntLeg_ID}=$Acid;
  $Acids{$IntLeg_ID}=$Acid;
  $Durations{$IntLeg_ID}=$Duration;
  $CallBegin{$IntLeg_ID}=$CallBegin;
  $CallEnd{$IntLeg_ID}=$CallEnd;
  $CallEndedSIPCodes{$IntLeg_ID}=$SipCode;
  $CallEndedAction{$IntLeg_ID}=$Action;
  $CallEndedResults{$IntLeg_ID}=$Result;

  $Type{$IntLeg_ID} = "SipMT";
  if ( ! $CallDur{$IntLeg_ID} ) {
    $CallDur{$IntLeg_ID} = $Duration;
  } else {
    $CallDur{$IntLeg_ID} = $CallDur{$IntLeg_ID} + $Duration;
  }
  $MTCallDur = $MTCallDur + $Duration;
  $TotalDur = $TotalDur + $Duration;

  push( @Activity, "$LogTime : $SIPID ended the call from $Callee ( Result = $SipCode, Duration = $Duration )" );
}

sub ShowSummary {

  my $AcidCount = scalar ( keys %CallAcids );
  if ( $opt_a ) {
    foreach my $loop ( sort ( keys ( %CallAcids ))) {
      print "Acid $loop had call activity $CallAcids{$loop} times.\n";
    }
    print "\n";
    foreach my $loop ( sort ( keys ( %SMSAcids ))) {
      print "Acid $loop had sms activity $SMSAcids{$loop} times.\n";
    }
    print "\n";
  }

  # Someone wants a report
  &Dump_ACIDs if ( $opt_D );
  &Show_SAReport if ( $opt_SA );
  &Show_Report if ( $opt_R );
  &Show_Stats if ( $opt_S );
}

sub convert_time { 
  my $time = shift; 
  my $mins = int($time / 60);
  my $days = int($time / 86400); 
  $time -= ($days * 86400); 
  my $hours = int($time / 3600); 
  $time -= ($hours * 3600); 
  my $minutes = int($time / 60); 
  my $seconds = $time % 60; 
  
  $days = $days < 1 ? '' : $days .'d '; 
  $hours = $hours < 1 ? '' : $hours .'h '; 
  $minutes = $minutes < 1 ? '' : $minutes . 'm '; 
  $time = $days . $hours . $minutes . $seconds . 's' . " ( $mins mins )"; 
  return $time; 
}

sub convert_time_short { 
  my $time = shift; 
  my $days = int($time / 86400); 
  $time -= ($days * 86400); 
  my $hours = int($time / 3600); 
  $time -= ($hours * 3600); 
  my $minutes = int($time / 60); 
  my $seconds = $time % 60; 
  $minutes++ if $seconds > 30;
  
  $days = $days < 1 ? '' : $days .'d '; 
  $hours = $hours < 1 ? '' : $hours .'h '; 
  $minutes = $minutes < 1 ? '' : $minutes . 'm '; 
  $time = $days . $hours . $minutes; 
  return $time; 
}

sub Show_Report {
  no warnings 'uninitialized';
  $CallAttempts = $MOCallAttempts + $MTCallAttempts;
  $GoodCallAttempts = $GoodMOCallAttempts + $GoodMTCallAttempts;
  $BadCallAttempts = $BadMOCallAttempts + $BadMTCallAttempts;
  #
  $SMSAttempts = $MOSMSAttempts + $MTSMSAttempts;
  $GoodSMSAttempts = $GoodMOSMSAttempts + $GoodMTSMSAttempts;
  $BadSMSAttempts = $BadMOSMSAttempts + $BadMTSMSAttempts;
  use warnings;

  my $AcidCount = scalar ( keys %CallAcids );
  if ( $opt_R ) {
    print "\n";
    print "These statistics reflect the success of the call setup and teardown;  \n";
    print "  they do not reflect call performance, dropped calls and app problems.\n";
    print "Failed call counts, that are used to calculate call and text success rates,\n";
    print "  are calls with last SIP response code of 403, 408, 409, 410, 482, 500, \n";
    print "  503, and 504\n";
    print "SIP codes of 480, 486 are included in these statistics.\n";
    print "SIP code 404 has been removed from the error list as more indicative of\n";
    print "  user error than network or system errors.\n";
    print "Test units and Challenger data are not included in this report. \n";
  }


  if ( ( $CallAttempts == 0 ) && ( $SMSAttempts == 0 )) {
    print "\n\n";
    print "No calls recorded.\n";
    print "  Make sure there are some other than test tails.\n";
    print "\n\n";
    exit 0;
  }

  if ( $CallAttempts > 0 ) {
    if ( ! $opt_R ) {
      print "* Current failure SIP codes : @BadCodes\n" if ( $CallAttempts );
    }
    
    my %BadCodes;
    foreach $Loop ( keys ( %BadMO )) {
      $BadCodes{$Loop}= 0 if ( ! $BadCodes{$Loop} );
      $BadCodes{$Loop}=$BadCodes{$Loop} + $BadMO{$Loop};
    }
    foreach $Loop ( keys ( %BadMT )) {
      $BadCodes{$Loop}= 0 if ( ! $BadCodes{$Loop} );
      $BadCodes{$Loop}=$BadCodes{$Loop} + $BadMT{$Loop};
    }

    my $TotalAcidCount = scalar ( keys %TotalAcids );
    print "\n";
    print "$TotalAcidCount total acids active in the GGTT system\n" unless ( $opt_A );
    print "\n" unless ( $opt_A );
    print "\n" unless ( $opt_A );
    print "GGTT Talk Statistics:\n";
    print "  $AcidCount customers using GGTT Talk.\n";
    $GoodCallAttempts=0 if ( ! $GoodCallAttempts );
    if ( ! $CallAttempts ) {
      $Ratio=0;
    } else {
      $Ratio = $GoodCallAttempts/$CallAttempts;
    }
    if ( $Ratio == 1 ) {
      $Ratio = 100;
    } else {
     $Ratio=$Ratio*100;
     $Ratio = sprintf "%.2f", $Ratio;
    }
    print "  Talk call success ratio : ".$Ratio."% ($GoodCallAttempts/$CallAttempts)\n";
    print "  Total call minutes : ". convert_time($TotalDur)."\n";
    print "    Good calls : $GoodCallAttempts\n" if ( $GoodCallAttempts );
    print "    Failed calls : $BadCallAttempts\n" if ( $BadCallAttempts );
    foreach $Loop ( sort ( keys ( %BadCodes ))) {
      print "      Failure code $Loop: $BadCodes{$Loop}\n";
    }

    if ( $MOCallAttempts ) {
      print "\n";
      print "  Calls from aircraft : $MOCallAttempts\n";
      print "    Call minutes: ". convert_time($MOCallDur)."\n";
      print "    Longest MO Call: ". convert_time($MaxMODuration)." on $MaxMOAcid\n";
      print "    Good calls: $GoodMOCallAttempts\n" if ( $GoodMOCallAttempts );
      print "    Failed calls : $BadMOCallAttempts\n" if ( $BadMOCallAttempts );
      $GoodMOCallAttempts=0 if ( ! $GoodMOCallAttempts );
      if ( ! $MOCallAttempts ) {
        $Ratio=0;
      } else {
        $Ratio = $GoodMOCallAttempts/$MOCallAttempts;
      }
      if ( $Ratio == 1 ) {
        $Ratio = 100;
      } else {
       $Ratio=$Ratio*100;
       $Ratio = sprintf "%.2f", $Ratio;
      }
      foreach $Loop ( sort ( keys ( %BadMO ))) {
        print "      Failure code $Loop: $BadMO{$Loop}\n";
      }
      print "    * Success Ratio : ".$Ratio."% ($GoodMOCallAttempts/$MOCallAttempts)\n";
    } else {
      print "  No calls attempted from the aircraft.\n";
    }

    if ( $MTCallAttempts ) {
      print "  Calls to aircraft : $MTCallAttempts\n";
      print "    Call minutes : ". convert_time($MTCallDur)."\n";
      print "    Longest MT Call: ". convert_time($MaxMTDuration)." on $MaxMTAcid\n";
      print "    Good calls : $GoodMTCallAttempts\n" if ( $GoodMTCallAttempts );
      print "    Failed calls : $BadMTCallAttempts\n" if ( $BadMTCallAttempts );
      $GoodMTCallAttempts=0 if ( ! $GoodMTCallAttempts );
      if ( ! $MTCallAttempts ) {
        $Ratio=0;
      } else {
        $Ratio = $GoodMTCallAttempts/$MTCallAttempts;
      }
      if ( $Ratio == 1 ) {
        $Ratio = 100;
      } else {
       $Ratio=$Ratio*100;
       $Ratio = sprintf "%.2f", $Ratio;
      }
      foreach $Loop ( sort ( keys ( %BadMT ))) {
        print "      Failure code $Loop: $BadMT{$Loop}\n";
      }
      print "    * Success Ratio : ".$Ratio."% ($GoodMTCallAttempts/$MTCallAttempts)\n";
      print "\n";
    } else {
      print "  No calls attempted to the aircraft.\n";
      print "\n";
    }
  }

  if ( $CallAttempts > 0 ) {
    my $SMSAcidCount = scalar ( keys %SMSAcids );
    if ( $opt_a ) {
      foreach my $loop ( sort ( keys ( %SMSAcids ))) {
        print "Acid $loop had activity $SMSAcids{$loop} times.\n";
      }
      print "\n";
    }
  
    print "\n";
    print "GGTT Text Statistics:\n";
    print "  $SMSAcidCount customers using GGTT Text.\n";
    $GoodSMSAttempts=0 if ( ! $GoodSMSAttempts );
    if ( ! $SMSAttempts ) {
      $Ratio=0;
    } else {
      $Ratio = $GoodSMSAttempts/$SMSAttempts;
    }
    if ( $Ratio == 1 ) {
      $Ratio = 100;
    } else {
     $Ratio=$Ratio*100;
     $Ratio = sprintf "%.2f", $Ratio;
    }
    print "  Text success ratio : ".$Ratio."% ($GoodSMSAttempts/$SMSAttempts)\n";
  
    print "  Total messages transmitted : $SMSAttempts\n";
    print "    Good texts : $GoodSMSAttempts\n" if ( $GoodSMSAttempts );
    print "    Failed texts : $BadSMSAttempts\n" if ( $BadSMSAttempts );
    foreach $Loop ( sort ( keys ( %BadCodes ))) {
      print "      Failure code $Loop: $BadSMSCodes{$Loop}\n" if ( $BadSMSCodes{$Loop} > 0);
    }
  
    if ( $MOSMSAttempts ) {
      print "\n";
      print "  Texts from aircraft : $MOSMSAttempts\n";
      print "    Good texts : $GoodMOSMSAttempts\n" if ( $GoodMOSMSAttempts );
      print "    Failed texts  : $BadMOSMSAttempts\n" if ( $BadMOSMSAttempts );
      foreach $Loop ( sort ( keys ( %BadMOSMS ))) {
        print "        Failure code $Loop: $BadMOSMS{$Loop}\n" if ( $BadMOSMS{$Loop} > 0);
      }
      $GoodMOSMSAttempts=0 if ( ! $GoodMOSMSAttempts );
      if ( ! $MOSMSAttempts ) {
        $Ratio=0;
      } else {
        $Ratio = $GoodMOSMSAttempts/$MOSMSAttempts;
      }
      if ( $Ratio == 1 ) {
        $Ratio = 100;
      } else {
        $Ratio=$Ratio*100;
        $Ratio = sprintf "%.2f", $Ratio;
      }
      print "    * Success ratio : ".$Ratio."% ($GoodSMSAttempts/$SMSAttempts)\n";
    } else {
      print "  No texts attempted from the aircraft.\n";
    }
    if ( $MTSMSAttempts ) {
      print "  Texts to aircraft  : $MTSMSAttempts\n";
      print "    Good texts  : $GoodMTSMSAttempts\n" if ( $GoodMTSMSAttempts );
      print "    Failed texts  : $BadMTSMSAttempts\n" if ( $BadMTSMSAttempts );
      foreach $Loop ( sort ( keys ( %BadMTSMS ))) {
        print "        Failure code $Loop: $BadMTSMS{$Loop}\n" if ( $BadMTSMS{$Loop} > 0);
      }
      $GoodMTSMSAttempts=0 if ( ! $GoodMTSMSAttempts );
      if ( ! $MTSMSAttempts ) {
        $Ratio=0;
      } else {
        $Ratio = $GoodMTSMSAttempts/$MTSMSAttempts;
      }
      if ( $Ratio == 1 ) {
        $Ratio = 100;
      } else {
        $Ratio=$Ratio*100;
        $Ratio = sprintf "%.2f", $Ratio;
      }
      print "    * Success ratio : ".$Ratio."% ($GoodSMSAttempts/$SMSAttempts)\n";
    } else {
      print "  No texts attempted to the aircraft.\n";
    }
  } 
  
  if ( $opt_R ) {
    print "\n"; 
    print "Code Legend:\n";
    print "  https://en.wikipedia.org/wiki/List_of_SIP_response_codes\n";
    print "  403 : Forbidden.  The server understood the request, but is refusing to fulfill it.\n";
    print "  408 : Request Timeout.   Couldn't find the user in time.\n";
    print "  409 : Conflict.  User already registered.\n";
    print "  410 : Gone.  The user existed once, but is not available here any more\n";
    print "  480 : Temporarily Unavailable.  Callee currently unavailable.\n";
    print "  486 : Busy Here.  Callee is busy.\n";
    print "  482 : Loop Detected.  Server has detected a loop.\n";
    print "  500 : Server Internal Error.  The server could not fulfill the request due to some \n";
    print "          unexpected condition.\n";
    print "  503 : Service Unavailable.  The server is undergoing maintenance or is temporarily\n";
    print "          overloaded and so cannot process the request. A \"Retry-After\" header field may\n";
    print "          specify when the client may reattempt its request.\n";
    print "  504 : Server Time-out.  The server attempted to access another server in attempting to\n";
    print "          process the request, and did not receive a prompt response.\n";
    print "\n";
  }
}


sub Show_SAReport {
  no warnings 'uninitialized';
  $CallAttempts = $MOCallAttempts + $MTCallAttempts;
  $GoodCallAttempts = $GoodMOCallAttempts + $GoodMTCallAttempts;
  $BadCallAttempts = $BadMOCallAttempts + $BadMTCallAttempts;
  #
  $SMSAttempts = $MOSMSAttempts + $MTSMSAttempts;
  $GoodSMSAttempts = $GoodMOSMSAttempts + $GoodMTSMSAttempts;
  $BadSMSAttempts = $BadMOSMSAttempts + $BadMTSMSAttempts;
  use warnings;

  my $AcidCount = scalar ( keys %CallAcids );

  if ( ( $CallAttempts == 0 ) && ( $SMSAttempts == 0 )) {
    print "\n\n";
    print "No calls recorded.\n";
    print "  Make sure there are some other than test tails.\n";
    print "\n\n";
    exit 0;
  }
  print "\n";

  if ( $CallAttempts > 0 ) {
    my %BadCodes;
    foreach $Loop ( keys ( %BadMO )) {
      $BadCodes{$Loop}= 0 if ( ! $BadCodes{$Loop} );
      $BadCodes{$Loop}=$BadCodes{$Loop} + $BadMO{$Loop};
    }
    foreach $Loop ( keys ( %BadMT )) {
      $BadCodes{$Loop}= 0 if ( ! $BadCodes{$Loop} );
      $BadCodes{$Loop}=$BadCodes{$Loop} + $BadMT{$Loop};
    }

    my $TotalAcidCount = scalar ( keys %TotalAcids );
    print "We saw $TotalAcidCount aircraft used GoGo Text and Talk\n" unless ( $opt_A );
    $GoodCallAttempts=0 if ( ! $GoodCallAttempts );
    if ( ! $CallAttempts ) {
      $Ratio=0;
    } else {
      $Ratio = $GoodCallAttempts/$CallAttempts;
    }
    if ( $Ratio == 1 ) {
      $Ratio = 100;
    } else {
     $Ratio=$Ratio*100;
     $Ratio = sprintf "%.2f", $Ratio;
    }
    print "$CallAttempts calls were placed from $AcidCount aircraft with a total duration of ".convert_time($TotalDur)." and ".$Ratio."% success rate.\n";
    print "  The longest mobile originated call had a total duration of ".convert_time($MaxMODuration)." on $MaxMOAcid\n";
    print "  The longest mobile terminated call had a total duration of ".convert_time($MaxMTDuration)." on $MaxMTAcid\n";
  }

  if ( $CallAttempts > 0 ) {
    my $SMSAcidCount = scalar ( keys %SMSAcids );
    $GoodSMSAttempts=0 if ( ! $GoodSMSAttempts );
    if ( ! $SMSAttempts ) {
      $Ratio=0;
    } else {
      $Ratio = $GoodSMSAttempts/$SMSAttempts;
    }
    if ( $Ratio == 1 ) {
      $Ratio = 100;
    } else {
     $Ratio=$Ratio*100;
     $Ratio = sprintf "%.2f", $Ratio;
    }
    print "$SMSAttempts texts were transmitted from $SMSAcidCount aircraft with ".$Ratio."% success rate.\n";
  } 
  print "\n";
}

sub TracePhone {
  print "\n\n";
  my $Entries=$#Activity+1;
  print "$Entries entries found for $opt_p\n";
  foreach $Loop (0..$#Activity) {
    print "$Loop : $Activity[$Loop]\n";
  }
  print "\n\n";

}

sub Show_Stats {
  no warnings 'uninitialized';
  $CallAttempts = $MOCallAttempts + $MTCallAttempts;
  $GoodCallAttempts = $GoodMOCallAttempts + $GoodMTCallAttempts;
  $BadCallAttempts = $BadMOCallAttempts + $BadMTCallAttempts;
  #
  $SMSAttempts = $MOSMSAttempts + $MTSMSAttempts;
  $GoodSMSAttempts = $GoodMOSMSAttempts + $GoodMTSMSAttempts;
  $BadSMSAttempts = $BadMOSMSAttempts + $BadMTSMSAttempts;
  use warnings;

  my $TotalAcidCount = scalar ( keys %TotalAcids );
  my $AcidCount = scalar ( keys %CallAcids );
  my $SMSAcidCount = scalar ( keys %SMSAcids );

  $GoodCallAttempts=0 if ( ! $GoodCallAttempts );
  $BadCallAttempts=0 if ( ! $BadCallAttempts );
  $GoodMOCallAttempts=0 if ( ! $GoodMOCallAttempts );
  $BadMOCallAttempts=0 if ( ! $BadMOCallAttempts );
  $GoodMTCallAttempts=0 if ( ! $GoodMTCallAttempts );
  $BadMTCallAttempts=0 if ( ! $BadMTCallAttempts );
  $GoodSMSAttempts=0 if ( ! $GoodSMSAttempts );
  $BadSMSAttempts=0 if ( ! $BadSMSAttempts );
  $MOSMSAttempts=0 if ( ! $MOSMSAttempts );
  $GoodMOSMSAttempts=0 if ( ! $GoodMOSMSAttempts );
  $BadMOSMSAttempts=0 if ( ! $BadMOSMSAttempts );
  $MTSMSAttempts=0 if ( ! $MTSMSAttempts );
  $GoodMTSMSAttempts=0 if ( ! $GoodMTSMSAttempts );
  $BadMTSMSAttempts=0 if ( ! $BadMTSMSAttempts );

  if ( $opt_f ) {
    $File = $opt_f;
  } else {
    $File = $opt_F;
  }
  $File =~ s/\*//g;


  # Standard Format Here
  if ( $opt_S eq "1" ) {
    if ( $opt_A ) {
      print "Date, Acid, Total Acids Seen, Call Acids Seen, CallAttempts, GoodCallAttempts, BadCallAttempts, Total Duration, GoodMOCallAttempts, BadMOCallAttempts, MO Duration, GoodMTCallAttempts, BadMTCallAttempts, MT Duration, SMSAcidCount, GoodSMSAttempts, BadSMSAttempts, MOSMSAttempts, GoodMOSMSAttempts, BadMOSMSAttempts, MTSMSAttempts, GoodMTSMSAttempts, BadMTSMSAttempts\n";
      print "$File, $opt_A, $TotalAcidCount, $AcidCount, $CallAttempts, $GoodCallAttempts, $BadCallAttempts, $TotalDur, $GoodMOCallAttempts, $BadMOCallAttempts, $MOCallDur, $GoodMTCallAttempts, $BadMTCallAttempts, $MTCallDur, $SMSAcidCount, $GoodSMSAttempts, $BadSMSAttempts, $MOSMSAttempts, $GoodMOSMSAttempts, $BadMOSMSAttempts, $MTSMSAttempts, $GoodMTSMSAttempts, $BadMTSMSAttempts\n";
    } else {
      print "Date, Total Acids Seen, Call Acids Seen, CallAttempts, GoodCallAttempts, BadCallAttempts, Total Duration, GoodMOCallAttempts, BadMOCallAttempts, MO Duration, GoodMTCallAttempts, BadMTCallAttempts, MT Duration, SMSAcidCount, GoodSMSAttempts, BadSMSAttempts, MOSMSAttempts, GoodMOSMSAttempts, BadMOSMSAttempts, MTSMSAttempts, GoodMTSMSAttempts, BadMTSMSAttempts\n";
      print "$File, $TotalAcidCount, $AcidCount, $CallAttempts, $GoodCallAttempts, $BadCallAttempts, $TotalDur, $GoodMOCallAttempts, $BadMOCallAttempts, $MOCallDur, $GoodMTCallAttempts, $BadMTCallAttempts, $MTCallDur, $SMSAcidCount, $GoodSMSAttempts, $BadSMSAttempts, $MOSMSAttempts, $GoodMOSMSAttempts, $BadMOSMSAttempts, $MTSMSAttempts, $GoodMTSMSAttempts, $BadMTSMSAttempts\n";
    }
  }

  # Shortened Format Here
  if ( $opt_S  eq "2") {
    $File =~ /(\d\d\d\d)(\d\d)(\d\d)/;
    my ($LocalDate) = "$2/$3/$1";
    if ( $opt_A ) {
      print "\$LocalDate :$LocalDate:\n";
      print "File, Date, Acid, Label 1, Total Acids Seen, Call Acids Seen, CallAttempts, TotalDur, Calc Mins, Calc Mins/AC,  MOCallDur, Label 2, SMS Acid Count, SMS Total, Texts/AC\n";
      print "$File, $LocalDate, $opt_A, minutes, $TotalAcidCount, $AcidCount, $CallAttempts, $TotalDur, ".($TotalDur/60).", ".($TotalDur/60)/$AcidCount.", $MOCallDur, Texts, $SMSAcidCount, $GoodSMSAttempts, ".($GoodSMSAttempts/$SMSAcidCount)."\n";
    } else {
      print "File, Date, Labal 1, Total Acid Seen, Call Acid Seen, CallAttempts, TotalDur,  Calc Mins, Calc Mins/AC, MOCallDur, Label 2, SMS Acid Count, SMS Total, Texts/AC\n";
      print "$File, $LocalDate, minutes, $TotalAcidCount, $AcidCount, $CallAttempts, $TotalDur,".($TotalDur/60).", ".($TotalDur/60)/$AcidCount.", $MOCallDur, Texts, $SMSAcidCount, $GoodSMSAttempts, ".($GoodSMSAttempts/$SMSAcidCount)."\n";
    }
  }

} 

sub Dump_ACIDs {
  my $Loop;

  print "Acids Found in this file:\n";
  foreach $Loop ( keys ( %Acids )) {
    print "  $Loop\n";
  }
}


sub ShowTransactions {
  #foreach 
  print "Transaction $opt_t\n";
  print $Transaction{$opt_t};
}


sub ProcessSsInviteReceivedUas {
  print "SsInviteReceived :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $Callee, $SIPID, $ExtLeg_ID, $Result) = $csv->fields();
  $PCAPID=$ExtLeg_ID;

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

}

sub ProcessCheckCalls {
  print "CheckCalls :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $Callee, $SIPID, undef, undef, undef, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

}

sub ProcessReadSubscriber {
  print "ReadSub :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $Callee, undef, $Result) = $csv->fields();

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

}

sub ProcessSsInviteSentUac {
  print "SsInviteSent :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $Caller, $Callee, $ExtLeg_ID, $Result) = $csv->fields();
  $PCAPID=$ExtLeg_ID;

  #trans.log.20131201235910:2031,01:12:2013-16:04:59,01:12:2013-16:04:59,02401301,0000,SsInviteSentUac,0020310000479967,0x00000000,0000,+17143085169,+18189892900,-ry61vdF3V7f-WUxPwrCuQ..,Success

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

}

sub ProcessSsInviteLeg1_Rsp {
  print "SsInviteSentLeg1 :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $LegStatus, $ExtLeg_ID, $Result) = $csv->fields();
  $PCAPID=$ExtLeg_ID;

  #trans.log.20131201235910:2031,01:12:2013-16:05:13,01:12:2013-16:05:13,02400701,0000,SsInviteLeg1_Rsp,0020310000479967,0x00000000,0200,connected,xnZPMAtOCxjRrLkp7W8UDn6l5oI6iwJJ,Success

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

}

sub ProcessSsInviteLeg2Rsp {
  print "SsInviteSentLeg2Rsp :$_:\n" if ( $Verbose );

  $csv->parse($_) or die $csv->error_diag();
  my ( undef, $LogTime, $CallStart, undef, undef, $Action, $TransID, undef, $SipCode, $LegStatus, $ExtLeg_ID, $Result) = $csv->fields();
  $PCAPID=$ExtLeg_ID;

  #trans.log.20131201235910:2031,01:12:2013-16:05:03,01:12:2013-16:05:03,02400801,0000,SsInviteLeg2Rsp,0020310000479967,0x00000000,0180,provisional,-ry61vdF3V7f-WUxPwrCuQ..,Success

  if ( $opt_r ) {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  } else {
    $Transaction{$TransID}="" if ( ! $Transaction{$TransID} );
    $Transaction{$TransID}=$Transaction{$TransID}." $_\n";
  }

}


sub ShowDurInfo {
  my $Bucket0 = 0; # Not Connected
  my $Bucket1 = 0; # Zero Length
  my $Bucket2 = 0; # 1 to 15 seconds
  my $Bucket3 = 0; # 16 to 30 seconds
  my $Bucket4 = 0; # 31 to 60 seconds
  my $Bucket5 = 0; # 61 to 180 seconds
  my $Bucket6 = 0; # 181 to 300 seconds
  my $Bucket7 = 0; # 300+ seconds
  my $Total = 0; 
  foreach my $IntLeg_ID ( sort ( keys ( %Calls ))) {
    $Total++;
    if ( $CallEndedResults{$IntLeg_ID} ne "Success" ) {
      $Bucket0++;
    } else {
      $Bucket1++ if ( $Durations{$IntLeg_ID} < 1 );
      $Bucket2++ if (( $Durations{$IntLeg_ID} > 0 ) && ( $Durations{$IntLeg_ID} < 16 ));
      $Bucket3++ if (( $Durations{$IntLeg_ID} > 15 ) && ( $Durations{$IntLeg_ID} < 31 ));
      $Bucket4++ if (( $Durations{$IntLeg_ID} > 30 ) && ( $Durations{$IntLeg_ID} < 61 ));
      $Bucket5++ if (( $Durations{$IntLeg_ID} > 60 ) && ( $Durations{$IntLeg_ID} < 181 ));
      $Bucket6++ if (( $Durations{$IntLeg_ID} > 180 ) && ( $Durations{$IntLeg_ID} < 301 ));
      $Bucket7++ if ( $Durations{$IntLeg_ID} > 300 );
    }
    if ( ! $CallEndedResults{$IntLeg_ID} ) {
      print "$LogTimes{$IntLeg_ID}, $IntLeg_ID, $CallEndedResults{$IntLeg_ID}\n";
    }
  }
  print "Duration Results:\n";
  print " Not Connected   = ".$Bucket0." ( ".sprintf("%.2f", ($Bucket0/$Total)*100)."% )\n";
  print " Zero Length     = ".$Bucket1." ( ".sprintf("%.2f", ($Bucket1/$Total)*100)."% )\n";
  print "   1 to 15 Secs  = ".$Bucket2." ( ".sprintf("%.2f", ($Bucket2/$Total)*100)."% )\n";
  print "  16 to 30 Secs  = ".$Bucket3." ( ".sprintf("%.2f", ($Bucket3/$Total)*100)."% )\n";
  print "  31 to 60 Secs  = ".$Bucket4." ( ".sprintf("%.2f", ($Bucket4/$Total)*100)."% )\n";
  print "  61 to 180 Secs = ".$Bucket5." ( ".sprintf("%.2f", ($Bucket5/$Total)*100)."% )\n";
  print " 180 to 300+Secs = ".$Bucket6." ( ".sprintf("%.2f", ($Bucket6/$Total)*100)."% )\n";
  print "      > 300 Secs = ".$Bucket7." ( ".sprintf("%.2f", ($Bucket7/$Total)*100)."% )\n";
  print "Total Calls: $Total\n";
  print "\n";
}

sub ShowCallInfo {
  print "Figuring out Call Information.\n";

  print "LogTimes, Transaction ID, IntLeg_ID, Acids, SIPIDS, Callee, CallCode, CallEndedCode, Durations, CallBegin, CallEnd, CallAction, SIPCodes, Results, CallEndedAction, CallEndedSIPCodes, CallEndedResults\n";
  foreach my $CallID ( sort ( keys ( %Calls ))) {
    print "$LogTimes{$CallID}, $CallTrans{$CallID}, $CallID, $CallLegAcids{$CallID}, $SIPIDS{$CallID}, $Callee{$CallID}, $CallCode{$CallID}, $CallEndedCode{$CallID}, $Durations{$CallID}, $CallBegin{$CallID}, $CallEnd{$CallID}, $CallAction{$CallID}, $CallSIPCodes{$CallID}, $CallResults{$CallID}, $CallEndedAction{$CallID}, $CallEndedSIPCodes{$CallID}, $Rule_Reasons{$CallID}, $CallEndedResults{$CallID}\n";
  }
}


sub ShowTextInfo {
  print "Figuring out Call Information.\n";

  print "LogTimes, Transaction ID, Action, CallCode,  SIPID, Callee, Content, ACID, Result\n";
  foreach my $TransID ( sort ( keys ( %Texts ))) {
    print "$TXTLogTimes{$TransID}, $TransID, $TXTAction{$TransID}, $TXTCallCode{$TransID}, $TXTSIPIDS{$TransID}, $TXTCallee{$TransID}, $TXTContent{$TransID}, $TXTID{$TransID}, $TXTResult{$TransID}\n";
  }
}

sub ShowSiPro {
  my $Count=0;
  foreach my $Phone ( sort ( values ( %Phones ))) {
    $Count++;
  }
  if ( $opt_b ) {
    print "Total Phones Counted : $Count\n";
    print " * Includes Test Acid based phones\n";
  } else {
    print "Total Phones Counted : $Count\n";
  }
}
