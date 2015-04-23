#!/usr/bin/perl -w
$| = 1;

use strict;
use diagnostics;
use Date::Parse;
use Date::Calc qw(:all);
use Date::Manip;
use Class::Date;
use DateTime;
use DateTime::Format::MySQL;
use Text::CSV;
my $csv = Text::CSV->new;

#


# GetOpt
use vars qw( $opt_h $opt_v $opt_t $opt_T $opt_p $opt_s );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v t=s T=s p s ");



use DBI;

if ( $opt_h ) {
  print "\n\n";
  print "Usage:  Check_Tail_Provisioning.pl -t <TAIL>\n";
  print "  -T <TAIL> = Specify the tail to check.\n";
  print "\n";
  print "Options: \n";
  print " -h = help (This screen)\n";
  print " -p = Show pattern match for Subnet checking\n";
  print " -s = short output\n";
  print "\n\n";
  exit 0;
}

&Define_Valid_Traffic_Policies;

# Check the date of the files
my $Date=`date`; chomp $Date;
my $MaxDiff="1200";

my $Verbose=0; $Verbose=1 if ( $opt_v );
if ( $opt_t )  {
  $opt_T=$opt_t;
}
my $Tail=$opt_T;
my $TailUser;
my %Valid_Policy;
my $Maximum_Subnet=135;
my $Minimum_Subnet=112;
my @SubnetGroups=( "112:127", "128:143", "144:159", "160:161", "14:14", "162:162" );
# BA Subnets
#   112-127 - Old Policy
#   128-143 - New Standard Policy
#   144-159 - New High Performance Policy
#   160-161 - ATG 8K
#   162-162 - ATG 1K / T&T-Email Only
# Lab Only
#   14
# CA
#   163-175 - ATG4
my @SubnetGroups=( "112:127", "128:143", "144:159", "160:175", "162:162" );
my $IP; my $IMSI; my $MDN; my $ESN; my $PDate; my $updateDate;
my $Policy="Undefined"; my $Status="Undefined"; my $PW="Undefined"; my $Subnet="Undefined";
my $Creds; my $Name;
# Needed for checking validity of files.
my $Diff;
my $Error=0;



# QNS AAA Information
my $UserInfo="/tmp/ba_users_info.csv";

# QNS AAA NASIP Information
my $TailInfo="/tmp/tails_info.csv";

my $Month=`/bin/date +%m`; chomp($Month);
my %Mons = ("01"=>'Jan',"02"=>'Feb',"03"=>'Mar',"04"=>'Apr',"05"=>'May',"06"=>'Jun',"07"=>'Jul',"08"=>'Aug',"09"=>'Sep',"10"=>'Oct',"11"=>'Nov',"12"=>'Dec');

my $dev; my $ino; my $mode; my $nlink; my $uid; my $gid; my $rdev; 
my $size; my  $atime; my $mtime; my $ctime; my $blksize; my $blocks;


# Lets get our SIM info
&Get_SIM_info("$Tail");

print "The current server time is $Date.\n" unless( $opt_s );
my $Currtime=str2time($Date);

if ( ! $opt_s ) {
  ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($UserInfo);
  $Diff=$Currtime - $mtime;
  if ( $Diff > $MaxDiff ) {
    print "** The User Info File is out of date.  Notify NetOps!\n";
    $Error=1;
  }


  ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($TailInfo);
  $Diff=$Currtime - $mtime;
  if ( $Diff > $MaxDiff ) {
    print "** The Tail Info File is out of date.  Notify NetOps!\n";
    $Error=1;
  }
}

# Get the difference


if ( $Tail !~ /^\d\d\d\d\d$/ ) {
  print "\n";
  print "This doesn't look like a BA tail ( i.e. 13115 ).\n";
  print "\n";
  exit 0;;
}

print "\n" unless( $opt_s );
print "Information for Tail $Tail:\n" unless( $opt_s );


#
# Process QNS AAA Subscriber Account Info
#
my $UserInfoFound=0;
open(USERINFO, "/bin/grep $Tail $UserInfo |") || die "Can't open $UserInfo :$!:\n";
while(<USERINFO>) {
  chomp;
  $csv->parse($_) or die $csv->error_diag();
  ( $Creds, $Policy, $Status, $PW, $Name ) = $csv->fields();
  $UserInfoFound=1;
}
$Creds="Missing" if ( ! $Creds );
$Name="Missing" if ( ! $Name );

if ( ! $UserInfoFound ) {
  print "  ** User info is missing.\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA Subscriber Information.\n";
  $Error=1;
}

my $CredTest=$Tail."\@airborne.aircell.com";
if ( ( $Creds ne $CredTest ) || ( $Name ne $CredTest ) ) {
  print "  ** Credentials in User info does not match $Tail\@airborne.aircell.com\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA Subscriber Information.\n";
  $Error=1;
} else {
  print "  Credentials test fine.\n" if ( $Verbose );
}

if ( $PW ne "aircell" ) {
  print "  ** Password does NOT match the standard.\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA Subscriber Information.\n";
  $Error=1;
} else {
  print "  QNS AAA Password matches the standard.\n" if ( $Verbose );
}

if ( $Creds ne $Name ) {
  print "  ** Credentials does not equal the Name Key.\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA Subscriber Information.\n";
  $Error=1;
} else {
  print "  Name Key matches the Credentials.\n" if ( $Verbose );
}

print "  Provisioning Status: $Status\n";
print "  Traffic Policy : $Policy\n" if ( $Verbose );
if ( ! $Valid_Policy{$Policy} ) {
  print "  ** This is not a valid Policy!!!\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA Subscriber Information.\n";
  $Error=1;
}

$PW="Undefined";

#
# Process QNS AAA Subscriber Account Info
#
my $TailInfoFound=0;
my $Command="/bin/grep BA[_-]$Tail $TailInfo";
open(TAILINFO, "$Command |") || die "Can't open $TailInfo :$!:\n";
while(<TAILINFO>) {
  chomp;
  $csv->parse($_) or die $csv->error_diag();
  print "  Tail Info Found:\n" if ( $Verbose );
  print "    $_\n" if ( $Verbose );
  ( $TailUser, $PW, $Subnet, undef ) = $csv->fields();
  $TailInfoFound=1;
}

if ( ! $TailInfoFound ) {
  print "  ** Tail info is missing.\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Information.\n";
  $Error=1;
}


if ( $TailUser ) {
  # Check our Subnet!
  my $Valid_Subnet=&Check_Subnet_Validity("$Subnet");
  print "  Defined User : $TailUser\n" if ( $Verbose );
  print "  ** Username - $TailUser -  is invalid\n" if ( $TailUser !~ /BA_$Tail/ );
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Information.\n" if ( $TailUser !~ /BA_$Tail/ );
  print "  Defined Subnet : $Subnet";
  if ( $Valid_Subnet eq "T" ) {
    print " is Valid.\n";
  } else {
    print " is NOT Valid.\n";
  } 
  if ( $Valid_Subnet eq "T" ) {
    print "    The subnet defined is in a valid for this tail.\n" if ( $Verbose );
  } else {
    print "  ** The subnet defined is NOT in a valid for this tail.\n";
    print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Information.\n";
    $Error=1;
  }
  &Print_Valid_Subnet_Pattern("$Subnet") if ( $opt_p );
} else {
  print "  ** Username is missing.\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Information.\n";
}


# What about the Radius Password?
if ( $PW ne "testing123" ) {
  print "  ** Radius Password does NOT match the standard.\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Information.\n";
  $Error=1;
} else {
  print "  Radius Password matches the standard.\n" if ( $Verbose );
}

# Info from Grande's DB
print "  IMSI : $IMSI\n";
print "  MDN : $MDN\n";
print "  ESN : $ESN\n";
print "  Provisioned : $PDate\n";
print "  Updated : $updateDate\n";
if ( $IMSI eq "Unknown" ) {
  print "  -- This may not be an error.  This database takes a minimum of 24 hours to synchronize with production.  Unknown means the data is not in the backup database, not that it is incorrect in the primary.\n"
}
# This doesn't appear to be valid
#print "  Provisioning #Date : $PDate\n";

#
# Lets check DS1 Tail Provisioning
#  ** Without this, Manufacturing will NOT work
open(INPUT, "/usr/local/bin/Check_DS1 $Tail |");
while(<INPUT>) {
  chomp;
  print "  $_ \n" if (( $Verbose ) || ( /\*\*/ ));
  $Error=1 if ( /There is a provisioning problem/);
}
close(INPUT);

#
# Lets check DS2 Tail Provisioning
#  ** Without this, Manufacturing will NOT work
open(INPUT, "/usr/local/bin/Check_DS2 $Tail |");
while(<INPUT>) {
  chomp;
  print "  $_ \n" if (( $Verbose ) || ( /\*\*/ ));
  $Error=1 if ( /There is a provisioning problem/);
}
close(INPUT);

#
# What was the last log uploaded?
#
my $TargetDir="/opt/log/atg/2014/".$Month."/".$Tail;
#if ( ! -d $TargetDir ) {
#  print "  -- There is no log directory for $Mons{$Month} (".$Month.")\n";
#  print "  -- THIS IS NOT THE PROVISIONING MISSING DIRECTORY PROBLEM!\n";
#}

open(USERINFO, "ls -1rt /opt/log/atg/201[45678]/*/$Tail/abs_logs/acpu_java 2>/dev/null | tail -1 |");
while(<USERINFO>) {
  chomp;
  my $LastLog=$_;
  if ( $LastLog eq "" ) {
    print "  This tail has not uploaded any log files.\n" if ( $Verbose );
  } else {
    print "  The last log file uploaded: $LastLog\n" if ( $Verbose );
  }
}


if ( ! $opt_s ) {
  print "\n";
  if ( $Error ) {
    print " ** Something is wrong above!  Please check for errors marked with \*\*.\n";
    print "\n";
  } else {
    print " Everything looks acceptable.\n";
    print "\n";
  }
    
}

########################
# Sub Procs Below Here #
########################
########################
sub Define_Valid_Traffic_Policies {
  $Valid_Policy{"GOGO-BA-75-Users"}=1;
}


sub Check_Subnet_Validity {
  my $Valid="F";
  my $Subnet=$_[0];
  my ( $First, $Second, $Third, $Fourth )=split('\.', $Subnet);


  foreach my $Loop  ( @SubnetGroups ) {
    my ( $Min, $Max )=split(":", $Loop);
    $Valid="T" if (( $Second >= $Min ) && ( $Second <= $Max ));
  }

  # Test last to prevent a valid 2nd from breaking these
  $Valid="F" if (( $First != 10 ) || ( $Fourth != 1 ) );

  return ( $Valid );
}


sub Print_Valid_Subnet_Pattern {
  my $Subnet=$_[0];
  print "\n";
  print "The subnet $Subnet needs to match the following pattern.\n";
  my ( $First, $Second, $Third, $Fourth )=split('\.', $Subnet);
  print "    The first octet must be 10.\n";
  print "    The second octet must be Greater than or equal to $Minimum_Subnet.\n";
  print "    The second octet must be Less than or equal to $Maximum_Subnet.\n";
  print "    The fourth octet must be 1\n";
  print "\n";
}


sub Get_SIM_info {
  my $Tail=$_[0];

  my $Host="10.241.1.93";
  my $Database="skynet";
  my $User="baOPS";
  my $Passwd="baOPS";

  # Make Connection to AAA
#  print "Connecting: DBI:mysql:database=$Database;host=$Host $User $Passwd\n" if ( $Verbose );

  my $dbh = DBI->connect("DBI:mysql:database=$Database;host=$Host", "$User", "$Passwd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;

  my $sth = $dbh->prepare("select imsi, mdn, esn, provisioned_date, updateDate from tails where tail=$Tail") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  my $numRows = $sth->rows;
  my @data = $sth->fetchrow_array();

  $IMSI=$data[0]; $IMSI="Unknown" if ( ! $IMSI );
  $MDN=$data[1]; $MDN="Unknown" if ( ! $MDN );
  $ESN=$data[2]; $ESN="Unknown" if ( ! $ESN );
  $PDate=$data[3]; $PDate="Unknown" if ( ! $PDate );
  $updateDate=$data[4]; $updateDate="Unknown" if ( ! $updateDate );
}
