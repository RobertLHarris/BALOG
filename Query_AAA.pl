#!/usr/bin/perl -w

use strict;
use diagnostics;

# GetOpt
use Getopt::Mixed;
use vars qw( $opt_h $opt_v $opt_T $opt_SD $opt_ED $opt_S $opt_usage $opt_o $opt_i $opt_t $opt_mb $opt_throttle $opt_subnet $opt_tail $opt_summary );
Getopt::Mixed::getOptions("h v T=s SD=s ED=s S=s o i t mb usage throttle subnet tail summary");

&ShowUsage if ( $opt_h );

# Lets set up our database connections
use DBI;

# AAA Info
my $aaadatabase="qns_report";
#my $aaahost="10.240.33.113";
my $aaahost="10.240.33.30";
my $aaadbuser="barouser";
my $aaadbpasswd="y9k4njs";
# RDR Info
my $rdrdatabase="QUOTA_RDR";
my $rdrhost="10.240.21.123";
my $rdrdbuser="rdr";
my $rdrdbpasswd="rdr\@g0g0";

#my $dbh = DBI->connect("DBI:mysql:database=$database;host=$host", "$dbuser", "$dbpasswd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;


# Variables
my %SDate; my %PTime; my %OMB; my %IMB; my %TMB; 
my %SID; my %IP; my %MAC; my %Usage; my %Tail; my %Subnet; 
my $FMB=0; 
my $ORatio;
my $IRatio;
my $TotalUsage=0; 
#
my $dbh;


my $Date;
my %Date;
my $Verbose=1 if ( $opt_v );
my $Tail=$opt_T;
my $StartDate;
if ( $opt_SD ) {
  $StartDate=$opt_SD;
  if ( $StartDate !~ /\d\d\d\d-\d\d-\d\d/ ) {
    print "Start Date Format is wrong.  Please try YYYY-DD-MM.\n";
    exit 0;
  }
}
my $EndDate;
if ( $opt_ED ) {
  $EndDate=$opt_ED;
  if ( $EndDate !~ /\d\d\d\d-\d\d-\d\d/ ) {
    print "End Date Format is wrong.  Please try YYYY-DD-MM.\n";
    exit 0;
  }
}
my $Subnet=$opt_S;

if ( $opt_mb ) {
  $opt_i=1;
  $opt_o=1;
  $opt_t=1;
}

&ShowTail if ( $opt_tail );
&ShowTailUsage if ( $opt_usage );
&ShowThrottle if ( $opt_throttle );
&ShowSubnetUsage if ( $opt_subnet );


# We're done here
exit 0;


########################
# Sub-Procs below here #
########################
sub ShowUsage {
  print "\n\n";
  print "Usage:  query_aaa.pl <options> <Command> -t <Tail> --SD <StartDate> --ED <EndDAte>\n";
  print "Command: \n";
  print " -h = help (This screen)\n";
  print " --usage = Show Usage for the tail on the date\n";
  print "   Requires -T, --SD and --ED \n";
  print " --throttle = Show throttle for the subnet on the date\n";
  print "   Requires -S and -D\n";
  print " --subnet = Show the usage for the subnet on the date\n";
  print "   Requires -D\n";
  print " --tail = Show the IP subnet range information for the tail\n";
  print "   Requires -T\n";
  print "\n";
  print "Required: \n";
  print " -S <Subnet> : Specify a tail to query on.\n";
  print " -T <Tail> : Specify a tail to query on.\n";
  print "     Date format is \"YYYY-MM-DD\"\n";
  print "\n";
  print "Options: \n";
  print "  -v  = Verbose output\n";
  print "  -o  = Show Output_MB\n";
  print "  -i  = Show Input_MB\n";
  print "  -t  = Show Total_MB\n";
  print " --mb = Show All Usage\n";
  print "\n\n\n";
  exit 0;
}


sub ShowTailUsage {
  my @data;

  if (( ! $Tail ) && ( ! $StartDate ) && ( $EndDate )) {
    print "\n";
    print "Options -T and -D are both required.\n";
    print "\n";
    exit 1;
  }
  # Make Connection to AAA
  $dbh = DBI->connect("DBI:mysql:database=$aaadatabase;host=$aaahost", "$aaadbuser", "$aaadbpasswd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;

  print "\n";
  print "Getting Data.\n" if ( $Verbose );
  # Now retrieve data from the data.

  my $sth;

  # Get Usage Details
  if ( ! $opt_summary ) {
    if (( $StartDate ) && ( $EndDate )) {
      print "select start_date,process_time,format(output_bytes/1024/1024,2) as Output_MB,format(input_bytes/1024/1024,2) as Input_MB,format((output_bytes+input_bytes)/1024/1024,2) as Total_MB,session_id,source_ip_address as ip,mac from qns_report.usage_archive where user_name like \"$Tail\@airborne%\" and start_date between \"$StartDate 00:00:00%\" and \"$EndDate 23:59:59%\" order by start_date asc\n\n" if ( $Verbose );
      $sth = $dbh->prepare("select start_date,process_time,format(output_bytes/1024/1024,2) as Output_MB,format(input_bytes/1024/1024,2) as Input_MB,format((output_bytes+input_bytes)/1024/1024,2) as Total_MB,session_id,source_ip_address as ip,mac from qns_report.usage_archive where user_name like \"$Tail\@airborne%\" and start_date between \"$StartDate 00:00:00%\" and \"$EndDate 23:59:59%\" order by start_date asc") || die "$?";
    } else {
      print "  Your date selections are wrong.  Try again.\n";
      exit 0;
    }

    $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

    # We need a header line
    print "StartDate,";
    print " Process_time,";
    print " Output_MB," if ( $opt_o);
    print " Input_MB," if ( $opt_i);
    print " Total_MB," if ( $opt_t);
    print " IP,";
    print " Session_ID,";
    print " MAC\n";

    undef(@data);
    while ( @data = $sth->fetchrow_array()) {
      #
      my $SID=$data[5]; 
  
      if ( ( !  $data[2] ) || ( !  $data[3] ) || ( !  $data[4] )) {
        print "AAA Data Error on $data[0] $data[1]\n";
        next;
      }

      #
      $SDate{$SID}=$data[0]; 
      $PTime{$SID}=$data[1]; 
      $OMB{$SID}=$data[2]; 
      $IMB{$SID}=$data[3]; 
      $TMB{$SID}=$data[4]; 
      $IP{$SID}=$data[6]; 
      $MAC{$SID}=$data[7];

      if ( $TMB{$SID} == 0 ) {
        $ORatio=0;
        $IRatio=0;
      } else {
        $ORatio=$OMB{$SID}/$TMB{$SID};
        $IRatio=$IMB{$SID}/$TMB{$SID};
      }
      print "$SDate{$SID},";
      print " $PTime{$SID},";
      print " $OMB{$SID}," if ( $opt_o);
      print " $IMB{$SID}," if ( $opt_i);
      print " $TMB{$SID}," if ( $opt_t);
      print " $IP{$SID},";
      print " $SID,";
      print " $MAC{$SID}";
      if ( $ORatio > .2 ) {
        print "\n  Output Ratio is $ORatio";
      }
      print "\n";
    }
  }

#return;

  # Get our Summary;
  my $Query="select count( source_ip_address), count( mac ), sum(format((output_bytes+input_bytes)/1024/1024,2) ) as Total_MB from qns_report.usage_archive where user_name like \"$Tail\@airborne%\" and start_date between \"$StartDate 00:00:00%\" and \"$EndDate 23:59:00%\"";
  if (( $StartDate ) && ( $EndDate )) {
    print "\$Query :$Query:\n" if ( $Verbose );
    $sth = $dbh->prepare("$Query") || die "$?";
  } else {
    print "  Your date selections are wrong.  Try again.\n";
    exit 0;
  }
  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;
  undef(@data);
  while ( @data = $sth->fetchrow_array()) {
    print "\@data :@data:\n" if ( $Verbose );
    print "There were $data[0] IP addresses from $data[1] MAC addresses which had a total usage of $data[2]MB\n";
  }
  $sth->finish();

  print "\n";
  print "Data done.\n" if ( $Verbose );
  print "\n";

}


sub ShowThrottle {

  if ( ( ! $Subnet ) && ( ! $Date )) {
    print "\n";
    print "Options -S and -D are both required.\n";
    print "\n";
    exit 1;
  }

  # Make Connection to RDR
  $dbh = DBI->connect("DBI:mysql:database=$rdrdatabase;host=$rdrhost", "$rdrdbuser", "$rdrdbpasswd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;

  print "\n";
  print "Getting Data.\n" if ( $Verbose );
  # Now retrieve data from the data.

  print "select * from QUOTA_BREACH_RDR where SUBSCRIBER_ID like \"$Subnet%\" and DATE_TIME like \"%$Date%\";\n" if ( $Verbose );
  my $sth = $dbh->prepare("select * from QUOTA_BREACH_RDR where SUBSCRIBER_ID like \"$Subnet%\" and DATE_TIME like \"%$Date%\";");

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  # We need a header line
  print "StartDate,";
  print " Process_time,";
  print " Output_MB," if ( $opt_o);
  print " Input_MB," if ( $opt_i);
  print " Total_MB," if ( $opt_t);
  print " IP,";
  print " Session_ID,";
  print " MAC\n";

  my $numRows = $sth->rows;
  while ( my @data = $sth->fetchrow_array()) {
    #
    my $Data=join(' : ', @data) if ( $Verbose );
    print "\$Data :$Data:\n" if ( $Verbose );
# StartDate, Process_time, IP, Session_ID, MAC


    my $SID=$data[3]; 
    #
    $SDate{$SID}=$data[0]; 
    $PTime{$SID}=$data[1]; 
    $IP{$SID}=$data[2]; 
    $MAC{$SID}=$data[4];

    print "$SDate{$SID},";
    print " $PTime{$SID},";
    print " $IP{$SID},";
    print " $SID,";
    print " $MAC{$SID}\n";
  }
  $sth->finish();

  print "\n";
  print "$numRows entries accounted for a total data for the flight: $FMB MB\n";
  print "Data done.\n" if ( $Verbose );
  print "\n";

}


sub ShowSubnetUsage {

  if ( ! $Date ) {
    print "\n";
    print "Options -D is required.\n";
    print "\n";
    exit 1;
  }

  # Make Connection to RDR
  $dbh = DBI->connect("DBI:mysql:database=$aaadatabase;host=$aaahost", "$aaadbuser", "$aaadbpasswd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;

  print "\n";
  print "Getting Data.\n" if ( $Verbose );
  # Now retrieve data from the data.

  my $sth = $dbh->prepare("select DATE_FORMAT(Start_Date, '%Y-%m-%d') as 'Usage Date' ,left(nas_ip_address,locate('.',nas_ip_address)-1) IP_Oct_1 ,substring(nas_ip_address, locate('.',nas_ip_address)+1,locate('.',nas_ip_address,locate('.',nas_ip_address)+1)-locate('.',nas_ip_address)-1) IP_Oct_2 ,sum(u.output_bytes + u.input_bytes)/1024/1024 as 'Total Usage Volume (Mb)' from usage_archive u where u.start_date >= \"$Date\" and left(nas_ip_address,locate('.',nas_ip_address)-1) <> '127' group by DATE_FORMAT(Start_Date, '%Y-%m-%d') ,left(nas_ip_address,locate('.',nas_ip_address)-1) ,substring(nas_ip_address, locate('.',nas_ip_address)+1,locate('.',nas_ip_address,locate('.',nas_ip_address)+1)-locate('.',nas_ip_address)-1) order by DATE_FORMAT(Start_Date, '%Y-%m-%d');");

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  # We need a header line
  print "StartDate,";
  print " Subnet,";
  print " Usage\n";

  my $numRows = $sth->rows;
  while ( my @data = $sth->fetchrow_array()) {
    #
    my $Data=join(' : ', @data) if ( $Verbose );
    print "\$Data :$Data:\n" if ( $Verbose );

    my $Subnet=$data[1].".".$data[2];

    $SDate{$Subnet}=$data[0]; 
    $Usage{$Subnet}=$data[3];
    $TotalUsage=$TotalUsage+$Usage{$Subnet};

    print "$SDate{$Subnet},";
    print " $Subnet,";
    print " $Usage{$Subnet}\n";
  }
  $sth->finish();

  print "\n";
  print "$numRows entries accounted for a total data for the flight: $TotalUsage MB\n";
  print "Data done.\n" if ( $Verbose );
  print "\n";

}


sub ShowTail {
  my $Subnet;

  print "\n";
  print "Getting Tail Subnet Info:\n";
  if ( ! $Tail ) {
    print "\n";
    print "Option -T is required.\n";
    print "\n";
    exit 1;
  }

  # Make Connection to RDR
  $dbh = DBI->connect("DBI:mysql:database=$aaadatabase;host=$aaahost", "$aaadbuser", "$aaadbpasswd", {'RaiseError' => 1}) || die "Couldn't connect to database: " . DBI->errstr;

  print "\n";
  print "Getting Data.\n" if ( $Verbose );
  # Now retrieve data from the data.

  print "select tail_number, source_ip_address, timestamp, session_id from qns_usage_record_day where tail_number like \"%$Tail%\";\n" if ( $Verbose );
  my $sth = $dbh->prepare("select tail_number, source_ip_address, timestamp, session_id from qns_usage_record_day where tail_number like \"%$Tail%\";");

  $sth->execute() || die "$?" or die "Couldn't execute statement: " . $sth->errstr;

  print "Tail,  IP,            Date,                Session\n";
  my $numRows = $sth->rows;
  while ( my @data = $sth->fetchrow_array()) {
    #
    my $Data=join(' : ', @data) if ( $Verbose );
    print "\$Data :$Data:\n" if ( $Verbose );
## tail_number, source_ip_address, timestamp, session_id
#
    my $SID=$data[3]; 
    #
    $Tail{$SID}=$data[0]; 
    $Subnet{$SID}=$data[1]; 
    $Date{$SID}=$data[2]; 

    $Subnet=$Subnet{$SID};
    $Subnet =~ s/\.\d+$//;

    print "$Tail{$SID},";
    print " $Subnet{$SID},";
    print " $Date{$SID},";
    print " $SID\n";
  }
  $sth->finish();

  print "\n";
  print "Subnet for tail $Tail : $Subnet\n";
  print "\n";

}

