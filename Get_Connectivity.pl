#!/usr/bin/perl -w
$| = 1;

use strict;
#use Date::Calc qw (Add_Delta_YMD);
use Date::Manip;
use Date::Manip::Delta;
use Date::Manip::Date;
use WWW::Mechanize;

# GetOpt
use vars qw( $opt_h $opt_v $opt_date );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v date=s");

#
my %FBO;
my $Verbose=0;  $Verbose=1 if ( $opt_v );

if ( $opt_h ) {
  print "\n\n";
  print "Usage:  Get_FBO.pl <options>\n";
  print "  -h : This menu \n";
  print "  -v : Verbose Output\n";
#  print " --date <YYYYMMDD> : Specify a particular date\n";
  print "\n\n";
  exit 0;
}


my $TopURL="http://baprojects01.aircell.com/PWA/BANetOps/Shared%20Documents/Forms/AllItems.aspx?RootFolder=%2FPWA%2FBANetOps%2FShared%20Documents%2FContent%20Delivery%2Freference%2FFBO%20Deployments%2FSFS";


%FBO=&Get_FBO_List;

foreach my $Loop ( sort ( keys ( %FBO ) ) ) {
  print "\$FBO{$Loop} :$FBO{$Loop}\n";
}

#sub Get_Second_Link {
#  my $URL=$_[0];
#  my $Target=$_[1];
#  my $Link; my $Filename;
#  my $mech;
#
#  print "  Getting SCE TUR and APP Data.\n";
#  $mech = WWW::Mechanize->new();
#  print "\$URL :$URL:\n" if ( $Verbose );
#  $mech->get($URL);
#
#  $Content=$mech->content;
#  # TUR
#  $Filename=$Target."-TUR.csv";
#  print "    Saving to $Filename.\n" if ( $Verbose );
#  $Link=($mech->find_link( n => 2 )->url);
#  print "\$Link :$Link:\n" if ( $Verbose );
#  $mech->get( $Link, ':content_file' => $Filename );
#
#  $mech = WWW::Mechanize->new();
#  $mech->get($URL);
#  $Content=$mech->content;
#  # APP
#  $Filename=$Target."-APP.csv";
#  print "    Saving to $Filename.\n" if ( $Verbose );
#  $Link=($mech->find_link( n => 3 )->url);
#  print "\$Link :$Link:\n" if ( $Verbose );
#  $mech->get( $Link, ':content_file' => $Filename );
#  print "\n" if ( $Verbose );
#}


sub Get_FBO_List {

  print "Getting List of FBO's from :\n";
  print "  $TopURL\n";
  my $mech = WWW::Mechanize->new();
  $mech->get($TopURL);

  #$mech->get( $link->[0] );

  my $Content=$mech->content;
  print "\$Content :$Content:\n" if ( $Verbose );
 
#  my $Link;
#  $Content =~ /.*HREF="(.*User_application_breakdown.*.html)"\>User Application Breakdown Report.*/;
#  if ( ! $1 ) {
#    $Link=0;
#  } else {
#    $Link=$1;
#  }
#  print "\$Content :$Content:\n" if ( $Verbose );
#  print "22\$Link :$Link:\n" if ( $Verbose );

#  return( $Link );
}

