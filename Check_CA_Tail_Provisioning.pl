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
use vars qw( $opt_h $opt_v $opt_T $opt_A $opt_p $opt_s );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v T=s A=s p s ");



use DBI;

if ( ( $opt_h ) || ( ! $opt_T ) || ( ! $opt_A ) ) {
  print "\n\n";
  print "Usage:  Check_Tail_Provisioning.pl -T <TAIL> -A <Airline Code>\n";
  print "  -T <TAIL> = Specify the tail to check.\n";
  print "  -A <AIRLINE_Code> = Specify the airline code to check.\n";
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

my $Verbose=0;
$Verbose=1 if ( $opt_v );

my $Loop;
my $Tail=$opt_T;
my $Airline=$opt_A;
my $TailUser;
my %TailUsers;
my %PWs;
my %Subnets;
my %Valid_Policy;
my $Maximum_Subnet=111;
my $Minimum_Subnet=19;
my $IP; my $IMSI; my $MDN; my $ESN; my $PDate;
my $Policy="Undefined"; my $Status="Undefined"; my $PW="Undefined"; my $Subnet="Undefined";
my $Creds; my $Name;
# Needed for checking validity of files.
my $Diff;
my $Error=0;

my $TailInfo="/tmp/tails_info.csv";

my $Month=`/bin/date +%m`; chomp($Month);
my %Mons = ("01"=>'Jan',"02"=>'Feb',"03"=>'Mar',"04"=>'Apr',"05"=>'May',"06"=>'Jun',"07"=>'Jul',"08"=>'Aug',"09"=>'Sep',"10"=>'Oct',"11"=>'Nov',"12"=>'Dec');

my $dev; my $ino; my $mode; my $nlink; my $uid; my $gid; my $rdev; 
my $size; my  $atime; my $mtime; my $ctime; my $blksize; my $blocks;

print "The current server time is $Date.\n" unless( $opt_s );
my $Currtime=str2time($Date);

if ( ! $opt_s ) {
  ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($TailInfo);
  $Diff=$Currtime - $mtime;
  if ( $Diff > $MaxDiff ) {
    print "** The Tail Info File is out of date.  Notify NetOps!\n";
    $Error=1;
  }
}


#
# Process QNS AAA Subscriber Account Info
#
print "\n" unless( $opt_s );
print "Information for Tail $Tail:\n" unless( $opt_s );

my $TailInfoFound=0;
my $Command="/bin/grep _$Tail $TailInfo | sort -r";
print "\$Command :$Command:\n" if ( $Verbose );

# First, is this a single or dual ACPU tail?
my $ACPUs=0;
open(TAILINFO, "$Command |") || die "Can't open $TailInfo :$!:\n";
while(<TAILINFO>) {
  chomp;
  $ACPUs++;
}
close(TAILINFO);

open(TAILINFO, "$Command |") || die "Can't open $TailInfo :$!:\n";
while(<TAILINFO>) {
  chomp;
  $csv->parse($_) or die $csv->error_diag();
  #print "\$_ :$_:\n" if ( $Verbose );
  ( $TailUser, $PW, $Subnet, undef ) = $csv->fields();
  #print "\$TailUser :$TailUser:\n" if ( $Verbose );
  $TailInfoFound=1;
  $TailUsers{$TailUser}=$TailUser;
  $PWs{$TailUser}=$PW;
  $Subnets{$TailUser}=$Subnet;
}
close(TAILINFO);


if ( ! $TailInfoFound ) {
  print "  ** no information found for $Tail\n";
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Infromation.\n";
  $Error=1;
}


# Future enhancement, fix the sort order so "-2" comes second.
#foreach $Loop ( sort ( {$TailUsers{$b} eq $TailUsers{$a}} keys %TailUsers ) ) {
foreach $Loop ( sort ( keys %TailUsers ) ) {
  print "-- Examining ATG $Loop.\n";
  print "\$Loop :$Loop:\n" if ( $Verbose );
  &Check_Subnet($Loop);
  &Check_Radius($Loop);
  &Check_Skynet($Loop);
  &Check_Log_Directorys($Loop);
  print "\n" if ( $Verbose );
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



exit 0;

######################
# Subnets below here #
######################

sub Check_Subnet {
  # Check our Subnet!
  my $TailUser=$TailUsers{$_[0]};
  my $Subnet=$Subnets{$_[0]};
  print "  Defined ATG Name : $TailUser\n";
  print "  ** Username is invalid\n" if ( $TailUser !~ /\w+_$Tail/ );
  print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Infromation.\n" if ( $TailUser !~ /\w+_$Tail/ );
  print "  Defined Subnet : $Subnet\n";
  my $Valid_Subnet=&Check_Subnet_Validity("$Subnet");
  
  if ( $Valid_Subnet eq "T" ) {
    print "    This is a valid subnet based on the expected pattern.\n";
  } else {
    print "  ** This is NOT a valid subnet based on the expected pattern.\n";
    $Error=1;
  }
  &Print_Valid_Subnet_Pattern("$Subnet") if ( $opt_p );
}


# What about the Radius Password?
sub Check_Radius {
  my $TailUser=$TailUsers{$_[0]};
  my $PW=$PWs{$_[0]};

  if ( $PW ne "testing123" ) {
    print "  ** Radius Password does NOT match the standard.\n";
    print "  ** Contact dcteam\@gogoair.com group about a problem with the QNS AAA NASIP Infromation.\n";
    $Error=1;
  } else {
    print "  Radius Password matches the standard.\n";
  }
}


sub Check_Skynet {
  my $TailUser=$TailUsers{$_[0]};

  # Lets get our SIM info
  &Get_SIM_info("$TailUser");

  # Info from Grande's DB
  print "  IMSI : $IMSI\n";
  print "  MDN : $MDN\n";
  print "  ESN : $ESN\n";
  if ( $IMSI eq "Unknown" ) {
    print "  -- This may not be an error.  This database takes a minimum of 24 hours to synchronize with production.  Unknown means the data is not in the backup database, not that it is incorrect in the primary.\n"
  }
  # This doesn't appear to be valid
  #print "  Provisioning #Date : $PDate\n";
}

sub Check_Log_Directorys {
  my $TailUser=$_[0];
  $TailUser =~ m/\w+_(.*)_\d+_\d+_\d+/;
  my $Tail=$1;

  print "Checking Directories for $TailUser\n" if ( $Verbose );
  if ( $Tail =~ /-2/ ) {
    print "  No Provisioning directory for the Second ATG expected.\n";
    return;
  }
  #
  # Lets check DS1 Tail Provisioning
  #  ** Without this, Manufacturing will NOT work
  print "Checking DS1 for $TailUser\n" if ( $Verbose );
  print "/usr/local/bin/Check_DS1 $Tail \n" if ( $Verbose );
  open(INPUT, "/usr/local/bin/Check_DS1 $Tail |");
  while(<INPUT>) {
    chomp;
    print "  $_ \n";
  }
  close(INPUT);

  #
  # Lets check DS2 Tail Provisioning
  #  ** Without this, Manufacturing will NOT work
  print "Checking DS2 for $TailUser\n" if ( $Verbose );
  print "/usr/local/bin/Check_DS2_CA $Tail $Airline \n" if ( $Verbose );
  open(INPUT, "/usr/local/bin/Check_DS2_CA $Tail $Airline |");
  while(<INPUT>) {
    chomp;
    print "  $_ \n";
  }
  close(INPUT);
}


sub Define_Valid_Traffic_Policies {
  $Valid_Policy{"GOGO-BA-75-Users"}=1;
}


sub Check_Subnet_Validity {
  my $Valid="T";
  my $Subnet=$_[0];
  my ( $First, $Second, $Third, $Fourth )=split('\.', $Subnet);

  if ( $Subnet eq "Undefined" ) {
    $Valid="F"; 
  } else {
    $Valid="F" if (( $First != 10 ) || ( $Fourth != 1 ) );
    $Valid="F" if (( $Second < $Minimum_Subnet ) || ( $Second > $Maximum_Subnet ) );
  }

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
  my $TailUser=$_[0];
  $TailUser =~ m/\w+_(.*)_\d+_\d+_\d+/;
  my $Tail=$1;

  print "\$TailUser :$TailUser:\n" if ( $Verbose );
  print "\$Tail :$Tail:\n" if ( $Verbose );

  my $Host="10.241.1.93";
  my $Database="skynet";
  my $User="baOPS";
  my $Passwd="baOPS";

  # Make Connection to AAA
  my $dbh = DBI->connect("DBI:mysql:database=$Database;host=$Host", "$User", "$Passwd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;

  my $sth = $dbh->prepare("select imsi, mdn, esn, provisioned_date from tails where tail like '%$Tail'") || die "$?";

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  my $numRows = $sth->rows;
  my @data = $sth->fetchrow_array();

  $IMSI=$data[0]; $IMSI="Unknown" if ( ! $IMSI );
  $MDN=$data[1]; $MDN="Unknown" if ( ! $MDN );
  $ESN=$data[2]; $ESN="Unknown" if ( ! $ESN );
  $PDate=$data[3]; $PDate="Unknown" if ( ! $PDate );
}
