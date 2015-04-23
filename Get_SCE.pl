#!/usr/bin/perl -w
$| = 1;

use strict;
#use Date::Calc qw (Add_Delta_YMD);
use Date::Manip;
use Date::Manip::Delta;
use Date::Manip::Date;
use WWW::Mechanize;

# GetOpt
use vars qw( $opt_h $opt_v $opt_date $opt_startdate $opt_finishdate $opt_o $opt_s $opt_q );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v date=s startdate=s finishdate=s o=s  s=s q ");

if ( $opt_h ) {
  print "\n\n";
  print "Usage:  Get_SCE.pl <options>\n";
  print "  -h : This menu \n";
  print "  -q : Quiet Mode\n";
  print "  -v : Verbose Output\n";
  print "  -o <path> : Directory to put the data into.\n";
  print "  -s AAA.BBB.CCC.,AAA.BBB.CCC.\n";
  print "   * Specify a comma separated list of subnets to report.\n";
  print "   * It must end with a dot on the end.  I.E. '172.20.152.'\n";
  print " --date <YYYYMMDD> : Specify a particular date\n";
  print " --startdate <YYYYMMDD> : Specify a particular date\n";
  print " --finishdate <YYYYMMDD> : Specify a particular date\n";
  print "  *** Start and end times will always do a full day ( 00:00-23:59 )\n";
  print "\n\n";
  exit 0;
}


my $Quiet=0;  $Quiet=1 if ( $opt_q );
my $Verbose=0;  $Verbose=1 if ( $opt_v );

my $Start_Time="00:00";
my $End_Time="23:59";
my $Subnet; my $Content;

my $URL="http://10.240.21.123/graph_TUR_usage_analyzer.html";

my @Subnets;
if ( $opt_s ) {
  @Subnets=split(',', $opt_s);
} else {
  # VZW Pre-move, commented out 2014/09/21
  #  '10.121.188.', '10.112.89.', '10.117.96.', '10.113.194.', '10.114.214.', '10.115.26.',
  # VZW New Subnets
  #  '10.134.1.', '10.134.2.', '10.134.3.', '10.134.4.', '10.134.5.', '10.134.6.',
  # Intel Subnets
  #  '10.120.105.', '10.121.193.', '10.122.160.', '10.116.197.', '10.118.79.', '10.120.108.');
  @Subnets=( 
              '10.120.105.', '10.121.193.', '10.122.160.', '10.116.197.', '10.118.79.', 
              '10.120.108.', '10.120.235.', '10.125.132.', 
              '10.134.1.', '10.134.2.', '10.134.3.', '10.134.4.', '10.134.5.', '10.134.6.'
  );
}

# Set or get our date
my $Yesterday; my $StartDate; my $FinishDate;
if ( $opt_date ) {
  print "Using date set $opt_date.\n" if ( $Verbose );
  $StartDate=$opt_date;
  $StartDate =~ s/-//g;
  $StartDate =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
  $StartDate=$1."-".$2."-".$3;
  $FinishDate=$StartDate;
} else {
  $Yesterday=ParseDate( "yesterday" );
  if ( $opt_startdate ) {
    print "Using start date set to $opt_startdate.\n" if ( $Verbose );
    $StartDate=$opt_startdate;
    $StartDate =~ s/-//g;
    $StartDate =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
    $StartDate=$1."-".$2."-".$3;
  } else { 
    $StartDate=substr( $Yesterday, 0, 8 );
    $StartDate =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
    $StartDate=$1."-".$2."-".$3;
  }
  if ( $opt_finishdate ) {
    print "Using finish date set to $opt_finishdate.\n" if ( $Verbose );
    $FinishDate=$opt_finishdate;
    $FinishDate =~ s/-//g;
    $FinishDate =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
    $FinishDate=$1."-".$2."-".$3;
  } else {
    $FinishDate=substr( $Yesterday, 0, 8 );
    $FinishDate =~ m/(\d\d\d\d)(\d\d)(\d\d)/;
    $FinishDate=$1."-".$2."-".$3;
  }
}

print "\$StartDate :$StartDate:\n" if ( $Verbose );
print "\$FinishDate :$FinishDate:\n" if ( $Verbose );

my $User=$ENV{"LOGNAME"};
my $TargetDir;
if ( $opt_o ) {
  $TargetDir=$opt_o;
  mkdir( $TargetDir ) if ( ! -d $TargetDir );
} else {
  $TargetDir="/tmp/SCE-".$User;
  mkdir( $TargetDir ) if ( ! -d $TargetDir );
}

print "\$TargetDir :$TargetDir:\n" if ( $Verbose );

foreach $Subnet ( @Subnets ) {
  $Subnet=$Subnet."." if ( $Subnet =~ /^\d+\.\d+\.\d+$/ );
  my $Target=$TargetDir."/".$Subnet."-".$StartDate;
  print "Getting $Subnet, $Target, $StartDate, $FinishDate\n";
  my $Link=&Get_First_Link( $Subnet, $StartDate, $FinishDate );

  if ( ! $Link ) {
    print "\n\n" unless ( $Quiet );
    print "Couldn't get base TUR link for $Subnet on $StartDate to $FinishDate.\n" unless ( $Quiet );
    print "\n\n" unless ( $Quiet );
    exit 0;
  } else {
    print "\$Link :$Link:\n" if ( $Verbose );
    &Get_Second_Link( $Link, $Target );
  }

  #  Keep as a reference as to what the resulting link looks like
  #  $Link="http://10.240.21.123/Reports/User_application_breakdown/TURs/User_application_breakdown/Reports/2014-08-25_22:55:51.Business_Aviation.10.121.188..2014-08-24.00:00.2014-08-24.23:59/DL.Business_Aviation.10.121.188..html";
}

sub Get_Second_Link {
  my $URL=$_[0];
  my $Target=$_[1];
  my $Link; my $Filename;
  my $mech;

  print "  Getting SCE TUR and APP Data.\n" unless ( $Quiet );
  $mech = WWW::Mechanize->new();
  print "\$URL :$URL:\n" if ( $Verbose );
  $mech->get($URL);

  $Content=$mech->content;
  # TUR
  $Filename=$Target."-TUR.csv";
  print "    Saving to $Filename.\n" if ( $Verbose );
  $Link=($mech->find_link( n => 2 )->url);
  print "\$Link :$Link:\n" if ( $Verbose );
  $mech->get( $Link, ':content_file' => $Filename );

  $mech = WWW::Mechanize->new();
  print "\$URL :$URL:\n";
  $mech->get($URL);
  $Content=$mech->content;
  # APP
  $Filename=$Target."-APP.csv";
  print "    Saving to $Filename.\n" if ( $Verbose );
  $Link=($mech->find_link( n => 3 )->url);
  print "\$Link :$Link:\n" if ( $Verbose );
  $mech->get( $Link, ':content_file' => $Filename );
  print "\n" if ( $Verbose );
}


sub Get_First_Link {
  my $Subnet=$_[0];
  my $StartDate=$_[1];
  my $FinishDate=$_[2];
  my $Airline;

  print "Getting SCE data for $Subnet on $StartDate to $FinishDate.\n" unless ( $Quiet );
  my $mech = WWW::Mechanize->new();
  print "\$URL :$URL:\n";
  $mech->get($URL);
  $Subnet =~ m/10.(\d+)\..*/;
  my $Second = $1;
  print "Subnet :$Subnet:\n" unless ( $Quiet );
  if ( $Second > 133 ) {
    $Airline="Business_Aviation_new";
  } else {
    $Airline="Business_Aviation";
  }
  print "  Sec Oct: $Second\n" unless ( $Quiet );
  print "  Airline: $Airline\n" unless ( $Quiet );
  $mech->submit_form(
      form_number => 1,
      fields      => { 'client_address' => $Subnet, 
                       'start_date' => $StartDate, 
                       'end_date' => $FinishDate, 
                       'start_time' => $Start_Time, 
                       'end_time' => $End_Time, 
                       'airline' => $Airline
                     },
  );
  die unless ($mech->success);

  #$mech->get( $link->[0] );

  $Content=$mech->content;
  print "\$Content :$Content:\n" if ( $Verbose );
 
  my $Link;
  $Content =~ /.*HREF="(.*User_application_breakdown.*.html)"\>User Application Breakdown Report.*/;
  my $TmpLink=$1;
  print "\$1 :$1:\n" if ( $Verbose );
  if ( ! $TmpLink ) {
    $Link=0;
  } else {
    $Link=$1;
  }
  print "22\$Link :$Link:\n" if ( $Verbose );

  return( $Link );
}

