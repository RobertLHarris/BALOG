#!/usr/bin/perl -w

use strict;
use diagnostics;
use DateTime qw();
use Date::Manip;

# We need to exit gracefully including untieing our hash
$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;

# For a hack to track what has been processed.
use Tie::File::AsHash;

# GetOpt
use vars qw( $opt_h $opt_v $opt_f $opt_T $opt_S $opt_P $opt_B $opt_D $opt_hash $opt_time $opt_month );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v S P B D hash=s time month=s ");


if ( $opt_h ) {
  print "\n\n";
  print "Usage:  Fleet_EDW_Dump.pl <options>\n";
  print " -h = help (This screen)\n";
  print "\n";
  print "Required: \n";
  print " --hash : Which set of Hashs's are we processing?\n";
  print "  a = Alpha (BXXXXX)\n";
  print "  1 = 10000, 12000, 14000\n";
  print "  2 = 11000, 13000, 15000\n";
  print " -S : Upload data to SIT\n";
  print " -P : Upload data to PROD\n";
  print " -B : Upload data to Both SIT and PROD\n";
  print "\n";
  print "Options: \n";
  print " --month : Pick a specific month ( 00..12 )\n";
  print " --time  : Limit time ( need to edit the script.\n";
  print " -D : DryRun.  Do not actually Execute\n";
  print "\n";
  print "\n";
  exit 0;
}


my $User=$ENV{"LOGNAME"};

# Are we processing odd or even?
my %ProcessedLogs;
my %NewProcessedLogs;
my $Hash;
my $HashFile;
my @Sources;

if ( ! $opt_hash ) {
  print "\n\n";
  print "Must define --hash\n";
  print "\n\n";
  exit 0;
} else {
  if ( $opt_hash eq "a" ) {
    $Hash="a";
    @Sources=( 'B' );
  } elsif ( $opt_hash == 1 ) {
    $Hash=1;
    @Sources=( '10', '12', '14' );
  } elsif ( $opt_hash == 2 ) {
    $Hash=2;
    @Sources=( '11', '13', '15' );
  } else {
    print "\n\n";
    print "Must define --hash as 1 or 2 \n";
    print "\n\n";
  }
}


if ( $User ne "balogsync" ) {
  print "\n\n";
  print " This must be run as user balogsync to prevent breaking the automatic loads.\n";
  print "  - To run manually, use:  \n";
  print "         sudo su - balogsync -c \"/usr/local/bin/Fleet_EDW_Dump.pl\"\n"; 
  print "\n\n";
  exit 0;
}

# If no option specified, assume it's from the cron and default to both.
if ( ( ! $opt_B ) && ( ! $opt_S ) ) {
#  $opt_S=1;
  $opt_P=1;
}

my $Target;
$Target=" -S" if ( $opt_S );
$Target.=" -P" if ( $opt_P );


# Hopefully this is obvious.
my $Verbose;
$Verbose=1 if ( $opt_v );

# Use -D if you want to test without actually running EDW_Dump.pl
my $DryRun=0;
$DryRun=1 if ( $opt_D );

my $Date=`/bin/date +%Y%m%dT%H%M%S`; chomp( $Date );
my $Year=`/bin/date +%Y`; chomp( $Year );
my $Month=`/bin/date +%m`; chomp( $Month );
my $Day=`/bin/date +%d`; chomp( $Day );
my $Subject; my @Errors; my $Loop; my @Found;
my $FirstError; my $LastError; my $Count;
my $Status;
my @TAILS;
my $SleepTimer=5;

# Lets force a specific month for processing
#$Month="08";
if ( $opt_month ) {
  $Month=$opt_month;
  $Month=substr( "0".$Month, -2 );
}

# How long should we look back
#   Normal:
my $MaxDays="60";
my $MinDays="0";
#  To get last week only
#my $MaxDays="14";
#my $MinDays="7";
#
my $Oldest=DateTime->now->subtract(days => $MaxDays); 
my $Newest=DateTime->now->subtract(days => $MinDays); 

# Use this to set a specfic date range.
#$Oldest="20140801";
#$Newest="20140801";

# Do not strip time from newest so we get the latest possible.
$Oldest =~ s/T\d\d:\d\d:\d\d/T00:00:00/g;

my $TimeOption;
if ( $opt_time ) {
  print "$Date : Processing files from $Month since between $Oldest until $Newest.\n";
  $TimeOption="-newermt $Oldest ! -newermt $Newest";
} else {
  print "$Date : Processing files from $Month.\n";
  $TimeOption="";
}


# Use last modified time
my $Type="-mtime ";
#
# How many console Logs to manage at once
my $Small_Loop=10;

my %Test_Tails;
&Define_Test_Tails;

# Define the log types we want the Extract script to process.
#  --nac and --nam says to NOT load all the console and messages files automatically.
my $LogTypes=" --nac --nam --airlink --console";

#
# Lets get our list of tails to check on for this month
#
print "Changing to /opt/log/atg/$Year/$Month\n";
chdir( "/opt/log/atg/$Year/$Month" );

&Process_Tail_List;

# If run with a specific month, do not run last month also
exit 0 if ( $opt_month );

#
# Lets get our list of tails to check on for last month
#
my $TmpMonth=ParseDate( "last month" );
$TmpMonth =~ m/(\d\d\d\d)(\d\d)\d\d.*/;
$Year=$1;
$Month=$2;
print "Changing to /opt/log/atg/$Year/$Month\n";
chdir( "/opt/log/atg/$Year/$Month" );

&Process_Tail_List;

exit 0;


########################
# Sub-Procs Below here #
########################
sub Process_Tail_List {
  my $SourceLoop;

  # What Tails to process

  foreach $SourceLoop ( @Sources ) {
    print " Processing Source :$SourceLoop:\n" if ( $Verbose );

    $HashFile="/opt/log/atg/$Year/$Month/ProcessedLogs-".$SourceLoop.".hash";
    print "Using Hashfile : $HashFile\n";
    my $Filter="^".$SourceLoop."[0-9][0-9][0-9]";
    print "  Filter :$Filter:\n";

    open(TAILS, "ls -1 | sort | grep $Filter |");
    #open(TAILS, "ls -1 | sort | grep $Filter | grep 10009 |");
    while(<TAILS>) {
      chomp;
      next if ( $Test_Tails{$_} );
      push(@TAILS, $_);
    }
    close(TAILS);
  
    # For faster Access next time
    my $TempFile="/tmp/PL-".$SourceLoop.".hash";
    print "/bin/cat $HashFile | /bin/sort > $TempFile; /bin/mv $TempFile $HashFile" if ( $Verbose );
    system("/bin/cat $HashFile | /bin/sort > $TempFile; /bin/mv $TempFile $HashFile") if ( ! $DryRun );
    #Get List of Processed
    &Get_Processed($HashFile);
    
    # Do the Actual Work
    &Process_Tails(@TAILS);
    undef(%ProcessedLogs);
    undef(@TAILS);
    print " Finished Source :$SourceLoop:\n" if ( $Verbose );
  }
}


sub Process_Tails {
  my @TAILS=@_;

  print "Scanning $#TAILS tail log dirs in /opt/log/atg/$Year/$Month\n";
  foreach $Loop (@TAILS) {
    my @FC; my $FC;
    my @DoMe; my $DoMe;
    my $ProcessedLoop;
    $FirstError="";
    $Count=0;
 
    print "\n\n" if ( $Verbose ); 
    chdir( "/opt/log/atg/$Year/$Month" ) if ( $Verbose );
    print "/bin/find $Loop -type f -iname $Loop*console* $TimeOption -print | sort |\n" if ( $Verbose );
    open(INPUT, "/bin/find $Loop -type f -iname $Loop*console* $TimeOption -print | sort |");
    while(<INPUT>) {
      chomp($_);
      # If this has key does NOT exist, we haven't processed it and should.
      if ( $Verbose ) {
        print "  Checking hash for $_."; 
        if ( ! $ProcessedLogs{$_} ) {
          print "    Entry not found.\n";
        } else {
          print "    Entry found :$ProcessedLogs{$_}:\n";
        }
      }
      if ( ! $ProcessedLogs{$_} ) {
        push(@FC, $_);
        push(@DoMe, $_);
      }
    }
  
    my $LogCount=$#FC+1;
    print "Tail :$Loop -- LogFiles to Process :$LogCount:\n" if ( $Verbose );
  
    next if ( $LogCount < 1 );
  
    print "Processing $LogCount Logs for $Loop\n";
  
    # Make the Loops manageable
    if ( $#FC > 15 ) {
      while (my @Small_Array = splice @DoMe, 0, $Small_Loop ) {
        $DoMe=join(',', @Small_Array );
        print "/usr/local/bin/Extract_ONE_Log.pl --so $LogTypes -T $Loop -m $Month --sd 01 --fd 31 --fc $DoMe | /usr/local/bin/EDW_Dump.pl $Target -T $Loop -f -\n" if ( $DryRun );
        system("/usr/local/bin/Extract_ONE_Log.pl --so $LogTypes -T $Loop -m $Month --sd 01 --fd 31 --fc $DoMe | /usr/local/bin/EDW_Dump.pl $Target -T $Loop -f -") if ( ! $DryRun );
        undef( @Small_Array );
      }
    }  else {
      $DoMe=join(',', @DoMe);
      print "/usr/local/bin/Extract_ONE_Log.pl --so $LogTypes -T $Loop -m $Month --sd 01 --fd 31 --fc $DoMe | /usr/local/bin/EDW_Dump.pl $Target -T $Loop -f -\n" if ( $DryRun );
      system("/usr/local/bin/Extract_ONE_Log.pl --so $LogTypes -T $Loop -m $Month --sd 01 --fd 31 --fc $DoMe | /usr/local/bin/EDW_Dump.pl $Target -T $Loop -f -") if ( ! $DryRun );
    }

    foreach $ProcessedLoop ( @FC ) {
      $NewProcessedLogs{$ProcessedLoop}=$Date if ( ! $ProcessedLogs{$ProcessedLoop} );
      $ProcessedLogs{$ProcessedLoop}=$Date;
    }

    print " About to write out ".scalar( keys ( %NewProcessedLogs ) )."\n" if ( $Verbose );
    &Write_Processed($HashFile);
    undef(%NewProcessedLogs);
    # Give the other Dumper a chance to get the DB
    sleep $SleepTimer;
  }
}

sub Get_Processed {
  my $HashFile=$_[0];
  my $Key; my $Value;

  open(INPUT, "<$HashFile");
  while(<INPUT>) {
    chomp;
    ($Key, $Value)=split(':', $_);
    $ProcessedLogs{$Key}=$Value;
  }
  close(INPUT);
}


sub Write_Processed {
  my $HashFile=$_[0];
  my $Key; my $Value;

  open(OUTPUT, ">>$HashFile") if ( ! $DryRun );;
  foreach $Key ( keys ( %NewProcessedLogs ) ) {
    print OUTPUT "$Key:$NewProcessedLogs{$Key}\n" if ( ! $DryRun );;
  }
  close(INPUT) if ( ! $DryRun );;
}


sub signal_handler {
    untie %ProcessedLogs;
    die "Caught a signal $!.  Untied ProcessedLogs and exiting";
    exit 0;
}


sub Define_Test_Tails {
  %Test_Tails = (
    "bahc1"=>'1',
    "01012"=>'1',
    "01009"=>'1',
    "01004"=>'1',
    "01007"=>'1',
    "10002"=>'1',
    "10004"=>'1',
    "10011"=>'1',
    "10022"=>'1',
    "10048"=>'1',
    "10053"=>'1',
    "10059"=>'1',
    "10063"=>'1',
    "10070"=>'1',
    "10072"=>'1',
    "10073"=>'1',
    "10074"=>'1',
    "10075"=>'1',
    "10080"=>'1',
    "10094"=>'1',
    "10107"=>'1',
    "10138"=>'1',
    "10168"=>'1',
    "10262"=>'1',
    "10211"=>'1',
    "10218"=>'1',
    "10409"=>'1',
    "10415"=>'1',
    "10440"=>'1',
    "10496"=>'1',
    "10596"=>'1',
    "10646"=>'1',
    "10732"=>'1',
    "10794"=>'1',
    "10564"=>'1',
    "10910"=>'1',
    "11021"=>'1',
    "11083"=>'1',
    "11611"=>'1',
    "11621"=>'1',
    "11224"=>'1',
    "11236"=>'1',
    "12034"=>'1',
    "12235"=>'1',
    "12642"=>'1'
  );
}

