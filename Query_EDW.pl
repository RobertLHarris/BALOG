#!/usr/bin/perl -w

use strict;
use diagnostics;

# GetOpt
use Getopt::Mixed;
use vars qw( $opt_h $opt_v $opt_T $opt_SD $opt_ED $opt_usage $opt_summary );
Getopt::Mixed::getOptions("h v T=s D=s SD=s ED=s usage throttle subnet summary");

my $Verbose=$opt_v;
&ShowUsage if ( $opt_h );

# Lets set up our Database connections
use DBI;

#ping 10.241.4.64
#ping pil-bl-edw-11.aircell.prod

# DB Info
my $dbuser="NETOPS_USR_RO";
my $dbpasswd="Up5!w0N#";
my $Database="ODS_Landing";
my $Port="1433";
my $Target="PROD";
my $Host="10.241.4.64";

# Test query from Jack
#select convert(varchar(10),ifu.usage_start_date,126) Usage_Date, ca.name Customer_Name, ifu.tail_nbr, count(ifu.session_id) Number_of_Sessions, sum(ifu.usage_download_volume + ifu.usage_upload_volume)/1024/1024 Total_Usage_Mb from edw.dbo.in_flight_usage_ba ifu inner join edw.dbo.DIM_ATG_SW_Version rv on rv.EDW_ATG_SW_VERSION_ID = ifu.edw_atg_sw_version_id inner join edw.dbo.customer_address ca on ca.edw_customer_address_id = ifu.edw_customer_address_id where ifu.tail_nbr not in (select tail_nbr from edw.dbo.BA_TEST_OR_DEMO_BOX_TAIL_NBR) and rv.prod_atg_release_ind = 'Y' and ifu.tail_nbr = '10338' --and ifu.session_id = '10119-1383353911390-10' and usage_start_date >= '2014-10-01 00:00:00.00' and usage_start_date < '2014-10-02 00:00:00.00' group by convert(varchar(10),ifu.usage_start_date,126), ca.name, ifu.tail_nbr
my $TestQuery="select convert(varchar(10),ifu.usage_start_date,126) Usage_Date, ca.name Customer_Name, ifu.tail_nbr, count(ifu.session_id) Number_of_Sessions, sum(ifu.usage_download_volume + ifu.usage_upload_volume)/1024/1024 Total_Usage_Mb from edw.dbo.in_flight_usage_ba ifu inner join edw.dbo.DIM_ATG_SW_Version rv on rv.EDW_ATG_SW_VERSION_ID = ifu.edw_atg_sw_version_id inner join edw.dbo.customer_address ca on ca.edw_customer_address_id = ifu.edw_customer_address_id where ifu.tail_nbr not in (select tail_nbr from edw.dbo.BA_TEST_OR_DEMO_BOX_TAIL_NBR) and rv.prod_atg_release_ind = 'Y' and ifu.tail_nbr = '10338' --and ifu.session_id = '10119-1383353911390-10' and usage_start_date >= '2014-10-01 00:00:00.00' and usage_start_date < '2014-10-02 00:00:00.00' group by convert(varchar(10),ifu.usage_start_date,126), ca.name, ifu.tail_nbr";

# Variables
my $dbh;
my $sth;
my $Tail=$opt_T;
my $StartDate=$opt_SD;
my $EndDate=$opt_ED;
my $TotalUsage=0; 

my $Summary;
$Summary=$opt_summary;

#$Tail=12487;
#$StartDate="2014-10-16";;
#$EndDate="2014-11-15";;

# Connect to the DB
&Create_DB_Connection;

#Get our Data
&Extract_Data_Detail if ( ! $Summary );
&Extract_Data_Summary;


# We're done here
exit 0;


########################
# Sub-Procs below here #
########################
sub ShowUsage {
  print "\n\n";
  print "Usage:  query_aaa.pl <options> <Command> -t <Tail> -d <Date>\n";
  print "Command: \n";
  print " -h = help (This screen)\n";
  print " --usage = Show Usage for the tail on the date\n";
  print "   Requires -T and -D\n";
  print "   or -T and ( --SD, --ED ) for Start and End range\n";
  print "\n";
  print " -T <Tail> : Specify a tail to query on.\n";
  print " -D <Date> : Specify a date to query.\n";
  print "     Date format is \"YYYY-MM-DD\"\n";
  print "\n";
  print "\n\n\n";
  exit 0;
}


sub Extract_Data_Detail {
  my @data; 
  my $Query;

   $Query="select convert(varchar(10),ifu.usage_start_date,126) Usage_Date, ca.name Customer_Name, ifu.tail_nbr, count(ifu.session_id) Number_of_Sessions, sum(ifu.usage_download_volume + ifu.usage_upload_volume)/1024/1024 Total_Usage_Mb from edw.dbo.in_flight_usage_ba ifu inner join edw.dbo.DIM_ATG_SW_Version rv on rv.EDW_ATG_SW_VERSION_ID = ifu.edw_atg_sw_version_id inner join edw.dbo.customer_address ca on ca.edw_customer_address_id = ifu.edw_customer_address_id where ifu.tail_nbr not in (select tail_nbr from edw.dbo.BA_TEST_OR_DEMO_BOX_TAIL_NBR) and rv.prod_atg_release_ind = 'Y' and ifu.tail_nbr = \"$Tail\" and usage_start_date >= \"$StartDate 00:00:00.00\" and usage_start_date < \"$EndDate 23:59:59.00\" group by convert(varchar(10),ifu.usage_start_date,126), ca.name, ifu.tail_nbr";

  print "\n";
  print "\$Query :$Query:\n" if ( $Verbose );
  print "\n" if ( $Verbose );
  $sth = $dbh->prepare("$Query") || die "Couldn't execute statement: " . $sth->errstr;
  $sth->execute() || die "Couldn't execute statement: " . $sth->errstr;

  print "Detailed EDW Usage data for $Tail from $StartDate through $EndDate\n";
  print "Date:       Customer:                     ATG SN:   Sessions:   MB Usage:\n" if ( ! $Summary );
  while ( @data = $sth->fetchrow_array()) {
    if ( $Summary ) {
      print "Customer :   $data[0]\n";
      print "ATG SN   :   $data[1]\n";
      print "Sessions :   $data[2]\n";
      print "MB Usage : ".sprintf("%10.2f", $data[3]);
    } else {
      my $Date=sprintf("%-12s", $data[0]);
      my $Customer=sprintf("%-30s", $data[1]);
      my $ATG=sprintf("%-10s", $data[2]);
      my $Sessions=sprintf("%-12d", $data[3]);
      my $Data=sprintf("%-10.2f", $data[4]);
      print $Date, $Customer,$ATG,   $Sessions,$Data."\n";

    }
  }
  print "\n";
}


sub Extract_Data_Summary {
  my @data; 
  my $Query;

   $Query="select ca.name Customer_Name, ifu.tail_nbr, count(ifu.session_id) Number_of_Sessions, sum(ifu.usage_download_volume + ifu.usage_upload_volume)/1024/1024 Total_Usage_Mb from edw.dbo.in_flight_usage_ba ifu inner join edw.dbo.DIM_ATG_SW_Version rv on rv.EDW_ATG_SW_VERSION_ID = ifu.edw_atg_sw_version_id inner join edw.dbo.customer_address ca on ca.edw_customer_address_id = ifu.edw_customer_address_id where ifu.tail_nbr not in (select tail_nbr from edw.dbo.BA_TEST_OR_DEMO_BOX_TAIL_NBR) and rv.prod_atg_release_ind = 'Y' and ifu.tail_nbr = \"$Tail\" and usage_start_date >= \"$StartDate 00:00:00.00\" and usage_start_date < \"$EndDate 23:59:59.00\" group by ca.name, ifu.tail_nbr";

  print "\$Query :$Query:\n" if ( $Verbose );
  print "\n" if ( $Verbose );
  $sth = $dbh->prepare("$Query") || die "Couldn't execute statement: " . $sth->errstr;
  $sth->execute() || die "Couldn't execute statement: " . $sth->errstr;

  print "Summary of EDW Usage data for $Tail from $StartDate through $EndDate\n";
  print "Date:       Customer:                     ATG SN:   Sessions:   MB Usage:\n" if ( ! $Summary );
  while ( @data = $sth->fetchrow_array()) {
      print "Customer :   $data[0]\n";
      print "ATG SN   :   $data[1]\n";
      print "Sessions :   $data[2]\n";
      print "MB Usage : ".sprintf("%10.2f", $data[3]);
  }
  print "\n";
}


sub Create_DB_Connection {

  print "\n" if ( $Verbose );
  print "Creating DB connection\n" if ( $Verbose );
  #
  # Manual Test:
  #  https://sites.google.com/site/fagonas/li/small-things
  #  /usr/local/sqsh/bin/sqsh -SSIT -U NETOPS_USR_RO -PUp5!w0N#
  # 
  my $dsn="dbi:ODBC:DRIVER={FreeTDS};Server=$Host;Port=1433;Database=$Database";
  $dbh =DBI->connect( "$dsn;UID=$dbuser;PWD=$dbpasswd;{ PrintError => 1, AutoCommit => 0 }" ) || die "Couldn't connect to D
atabase: " . DBI->errstr;

  if (! defined($dbh) ) {
    print "Error connecting to DSN '$Database'\n";
    print "Error was:\n";
    print "$DBI::errstr\n";         # $DBI::errstr is the error received from the SQL server
    exit 0;
  }
  print "  * Database connected.\n" if ( $Verbose );
  print "\n" if ( $Verbose );
}    

