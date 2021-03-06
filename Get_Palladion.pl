#!/usr/bin/perl -w

$|=1;

use strict;
use LWP::Simple;
use JSON qw( decode_json );
use XML::Simple;
use Data::Dumper;
use Scalar::Util qw/reftype/;
use DBI;

# We need to exit gracefully including untieing our hash
$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;

# GetOpt
use vars qw( $opt_h $opt_v $opt_f $opt_T $opt_S $opt_P $opt_B $opt_D );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v f=s T=s S P B D");

if ( ( ! $opt_S ) && ( ! $opt_P ) ) {
  print "\n\n";
  print "You must choose a target DB.  SIT (-S) and/or PROT (-P)\n";
  print "You may use -B to specify both.\n";
  print "\n\n";
  exit 0;
}

if ( $opt_B ) {
  $opt_S=1;
#  $opt_P=1;
}

# Get yesterday's data
my $TargetDate=`/bin/date --date="yesterday" +%Y-%m-%d`;  chomp( $TargetDate );
# Get a specific date
my @TargetDates=( 
                #  "2015-05-01", "2015-05-02", "2015-05-03", "2015-05-04", "2015-05-05", "2015-05-06", "2015-05-07", "2015-05-08", "2015-05-09",
		#  "2015-05-10", "2015-05-11", "2015-05-12", "2015-05-13", "2015-05-14", "2015-05-15", "2015-05-16", "2015-05-17", "2015-05-18", "2015-05-19",
		#  "2015-05-20", "2015-05-21", "2015-05-22", "2015-05-23", "2015-05-24", "2015-05-25", "2015-05-26", "2015-05-27", "2015-05-28", "2015-05-29",
		#  "2015-05-30", "2015-05-30", "2015-05-31",
		#  "2015-06-01", "2015-06-02", "2015-06-03", "2015-06-04", "2015-06-05", "2015-06-06", "2015-06-07", "2015-06-08"
		  "2015-06-15"
		 );

# Example URL Info
# admin:oracle http://10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00
my $JSONString;
my $Call;
my %Calls;
my $Counter=0;
my $Key;
my $Leg;
my $Testing=0;
my $Printout=0;
my $DBOut=1;
my $Loop;
my $Insert;
my @Output;
my $Hour;

my $Verbose=1 if ( $opt_v );

# Target Ends
#  /vq - Voice Quality
#  /messages - SIP Messages
#  /r/users/<userid>/calls - Calls belonging to the given platform user. The format of this resource is exactly like the format of the /r/calls resource.
#  /r/counters - The list of counters for the admin user and the `ALL' realm. 
#  /r/counters/<id> A representation of the given counter. 


# Lets set up our Database connections
my $dbhs; my $dbhp;
#   http://www.connectionstrings.com/sql-server/
if ( ! $opt_D ) {
  $dbhs=&Create_SIT_DB_Connection if ( $opt_S );
  $dbhp=&Create_PROD_DB_Connection if ( $opt_P );
}

# This lets us pull older data
foreach $TargetDate ( @TargetDates ) {
  print "Pulling Data for $TargetDate.\n" if ( $Verbose );
  @Output=();
  foreach $Hour ( 0..0 ) {
    &Get_Calls($Hour);
  }
  print "Inserting $#Output Lines for hour $Hour\n" if ( $Verbose );
  &Create_Output;
}


# Time to push the data


exit 0;

#
sub Get_Calls {
#  my $Hour=$_[0];
  $Hour=$_[0];
  $Hour=substr("0".$Hour, -2);

  my $User="admin:oracle";
  my $TargetBase="http://10.240.21.100/r/calls";
  my $TargetStart="$TargetDate+".$Hour.":00:00";
  my $TargetStop="$TargetDate+".$Hour.":19:59";
  my $Target=$TargetBase."/".$TargetStart."/".$TargetStop;

  print "Retrieving hour $Hour: $Target\n" if ( $Verbose );

  my $Converter = new JSON;
  print "Getting json $Target\n" if ( $Verbose );
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONString=$_;
  }


  my $SRC = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString) || die "Can't decode $JSONString :$!:\n";

  # This creates a REF to an array of each call's data.
  #  @{$DATA}[0]->{call_id} would have the ID for the first call
  my $DATA=${$SRC}{data};

  foreach my $Loop ( @{$DATA} ) {
    $Call=${$Loop}{call_id};
    #next if ( $Call ne "6160809412752578014" );
    print "Loop Data\n" if ( $Verbose );
#    print Dumper $Loop if ( $Verbose );
    print "Main Call :$Call:\n" if ( $Verbose );
    $Leg=0;

    # Call Details is the key for the part ( i.e. setup_time )
    foreach my $CallDetails ( keys( %{$Loop} ) ) {
      ${$Loop}{$CallDetails}="NULL" if ( !${$Loop}{$CallDetails} );
      print "  Loop \${$Loop}{$CallDetails} :${$Loop}{$CallDetails}:\n" if ( $Verbose );
      $Key=$Call.".".$Leg.".".$CallDetails;
      print "$Key : $Key\n" if ( $Printout );
      $Insert="$Call,$Leg,$CallDetails,${$Loop}{$CallDetails}" if ( $DBOut );
      my $RefType = reftype ${$Loop}{$CallDetails};
      push(@Output, "$Insert") if ( ( $DBOut )  && ( ! $RefType )  );
    }

    &Get_Details( $Call, ${$Loop}{"url"});
    &Get_VQ( $Call, ${$Loop}{"url"});

   # This limits it to just the first call...
   exit 0 if ( $Testing );
  }
}


sub Get_Details {
  my $Call=$_[0];
  my $URL=$_[1];
  print "\$URL :$URL:\n" if ( $Verbose );

  my $Value;


  my $User="admin:oracle";
  my $TargetBase="http://10.240.21.100/";
  my $Target=$TargetBase."/".$URL;


  my $Converter = new JSON;
  print "Getting json $Target\n" if ( $Verbose );
  print "/usr/bin/curl -k -L --digest -s --user $User $Target\n" if ( $Verbose );
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONString=$_;

    print "\$JSONString :$JSONString:\n" if ( $Verbose );
  }

  my $SRC = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString) || die "Can't decode $JSONString :$!:\n";
  print Dumper $SRC if ( $Verbose );

  foreach my $Details ( keys( %{$SRC} ) ) {
    $Leg=0;
    if ( ${$SRC}{$Details} ) {
      print "\${$SRC}{$Details} :${$SRC}{$Details}:\n" if ( $Verbose );
      # Insert Details
      my $RefType = reftype ${$SRC}{$Details};
      if ( ! $RefType ) {
        ${$SRC}{$Details}="NULL" if ( !${$SRC}{$Details} );
        print "  Loop \${$SRC}{$Details} :${$SRC}{$Details}:\n" if ( $Verbose );
        print "  \$Leg :$Leg:\n" if ( $Verbose );
        $Key=$Details;
        $Value=${$SRC}{$Details};
        print "$Key : $Key\n" if ( $Printout );
        $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
        print "\$Insert :$Insert:\n" if ( $Printout );
        push(@Output, "$Insert") if ( ( $DBOut )  && ( ! $RefType )  );
      }
    }
  }
 
  # Les walk the Legs if they exist 
  if ( ${$SRC}{legs} ) { 
    $Leg=0;
    print "Walking Legs\n" if ( $Verbose );
    my @Legs=${$SRC}{legs};
    foreach my $Loop ( @Legs ) {
      foreach my $Loop ( @{$Loop} ) {
        $Leg++;
        # Push values from Legs
        my @DataKeys=( 
                        'src_device_name', 'src_ip', 'dst_ip', 'dst_device_name', 'src_uri', 'setup_start_ts', 
                        'callid', 'code', 'dst_ua', 'dst_user', 'ruri', 'src_user', 'state_msg', 'type', 'dst_uri' );
        foreach my $Looper ( @DataKeys ) {
          $Key="$Looper";
          $Value=${$Loop}{$Looper}; $Value="Unknown" if ( ! defined( $Value ) );
          print "$Key : $Value\n" if ( $Printout );
          $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
          push(@Output, "$Insert") if ( $DBOut );
        }
      }
    }
  }
}


sub Get_VQ {
  my $Call=$_[0];
  my $URL=$_[1];
  $URL=$URL."/vq";
  print "\$URL :$URL:\n" if ( $Verbose );
  print "\$Call :$Call:\n" if ( $Verbose );
  print "\$URL :$URL:\n" if ( $Verbose );

  my $User="admin:oracle";
  my $TargetBase="http://10.240.21.100/";
  my $Target=$TargetBase."/".$URL;
  my $Value;

  $Leg=42;

  my $Converter = new JSON;
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONString=$_;
    
    print "\$JSONString :$JSONString:\n" if ( $Verbose );
  }

  my $SRC = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString) || die "Can't decode $JSONString :$!:\n";
  my $DATA=${$SRC}{data};
#  print Dumper $DATA if ( $Verbose );

  foreach my $Loop ( @{$DATA} ) {
    # Lets insert the SBC to Air leg Quality ( Ground to Air )
    if ( ( ${$Loop}{source} eq "OCOM-RTP-PROBE" ) && ( ${$Loop}{src_ip} eq "10.240.3.132" )  && ( ${$Loop}{data}{jitter_max} ) ) {
      # Direction
      #  Have to hard-code,  not in the data
      $Key="SBCtoAIR"."-direction";
      $Value="GroundToAir";
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # START_TS
      $Key="SBCtoAIR"."-start_ts";
      $Value=${$Loop}{start_ts}; $Value="Unknown" if ( ! $Value );
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # END_TS
      $Key="SBCtoAIR"."-end_ts";
      $Value=${$Loop}{start_ts}; $Value="Unknown" if ( ! $Value );
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # Push values from {data} within the tree
      my @DataKeys=( 'moscqe_avg', 'packets_lost', 'jitter_max', 'jitter_avg', 'moscqe_min', 'packets_received', 'r_factor', 'jitter_total' );
      foreach my $Looper ( @DataKeys ) {
        $Key="SBCtoAIR"."-$Looper";
        $Value=${$Loop}{data}{$Looper}; $Value="Unknown" if ( ! defined( $Value ) );
        print "$Key : $Value\n" if ( $Printout );
        $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
        push(@Output, "$Insert") if ( $DBOut );
      }
    }

    # Lets insert the Accuroam to SBC leg Quality ( Air to Ground )
    if ( ( ${$Loop}{source} eq "SBC-RTP" ) && ( ${$Loop}{src_ip} eq "10.240.82.85" ) && ( ${$Loop}{data}{jitter_max} ) ) {
      # sip_call_id
      $Key="ARtoSBC"."-sip_call_id";
      $Value=${$Loop}{sip_call_id}; $Value="Unknown" if ( ! $Value );
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # Direction
      $Key="ARtoSBC"."-direction";
      $Value="AirToGround";
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # START_TS
      $Key="ARtoSBC"."-start_ts";
      $Value=${$Loop}{start_ts}; $Value="Unknown" if ( ! $Value );
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # END_TS
      $Key="ARtoSBC"."-end_ts";
      $Value=${$Loop}{start_ts}; $Value="Unknown" if ( ! $Value );
      print "$Key : $Value\n"if ( $Printout );
      $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );
      # Push values from {data} within the tree
      my @DataKeys=( 'moscqe_avg', 'jitter_max', 'jitter_avg', 'packets_lost', 'packets_received', 'r_factor' );
      foreach my $Looper ( @DataKeys ) {
        $Key="ARtoSBC"."-$Looper";
        $Value=${$Loop}{data}{$Looper}; $Value="Unknown" if ( ! defined( $Value ) );
        print "$Key : $Value\n" if ( $Printout );
        $Insert="$Call,$Leg,$Key,$Value" if ( $DBOut );
        push(@Output, "$Insert") if ( $DBOut );
      }
    }
  }
}

#
# Processors here!
#
sub Process_Value {
  my $Call=$_[0];
  my $Ref=$_[1];

  my $RefType = reftype $Ref;
  if ( ! $RefType ) {
    #print "VQ $Ref\n" if ( $Verbose );
  } elsif ( $RefType eq "HASH" ) {
    #print "Found $RefType at $Ref\n" if ( $Verbose );
    &Walk_Hash( $Call, $Ref);
  } elsif ( $RefType eq "ARRAY" ) {
    #print "Found $RefType at $Ref\n" if ( $Verbose );
    &Walk_Array( $Call, $Ref);
  }
}


sub Walk_Array {
  my $Call=$_[0];
  my $Ref=$_[1];

  print "  Processing Array $Ref\n" if ( $Verbose );
  foreach my $Loop ( @{$Ref} ) {
    #print "  \$Loop :$Loop:\n" if ( $Verbose );
    &Process_Value( $Call, $Loop );
  }

}


sub Walk_Hash {
  my $Call=$_[0];
  my $Ref=$_[1];

  print "Hash 1\n" if ( $Verbose );
  print "  Processing Hash $Ref\n" if ( $Verbose );
  print " ** Leg $Leg\n" if ( $Verbose );
  foreach my $Loop ( keys ( %{$Ref} ) ) {
    $Key=$Call.".".$Leg.".".$Loop;
    ${$Ref}{$Loop}="NULL" if ( ! ${$Ref}{$Loop} );
    my $RefType = reftype ${$Ref}{$Loop};
    print "\$Loop :$Loop:\n";
    print "\${$Ref}{$Loop} :${$Ref}{$Loop}:\n";
    print "\$RefType :$RefType:\n";
    if ( ! $RefType ) {
      print "Key = $Key : Value = ${$Ref}{$Loop}\n";
      print "Key = $Key : Value = ${$Ref}{$Loop}\n" if ( $Printout );
      $Insert="$Call, $Leg, $Loop, ${$Ref}{$Loop}" if ( $DBOut );
      push(@Output, "$Insert") if ( $DBOut );

    } elsif ( $RefType eq "HASH" ) {
      print "Found $RefType at \${$Ref}{$Loop} - ${$Ref}{$Loop}\n" if ( $Verbose );
      &Walk_Hash( $Call, ${$Ref}{$Loop});
    } elsif ( $RefType eq "ARRAY" ) {
      print "Found $RefType at \${$Ref}{$Loop} - ${$Ref}{$Loop}\n" if ( $Verbose );
      &Walk_Array( $Call, ${$Ref}{$Loop});
    }
  }
}


sub Walk_Hash2 {
  my $Call=$_[0];
  my $Type=$_[1];
  my $Ref=$_[2];

  print "Hash 2\n" if ( $Verbose );
  print "  Processing Hash $Ref\n" if ( $Verbose );
  print " ** Leg $Leg\n" if ( $Verbose );
  foreach my $Loop ( keys ( %{$Ref} ) ) {
    $Key=$Call.".".$Leg.".".$Type.".".$Loop;
    print "$Key : ${$Ref}{$Loop}\n" if ( ( ${$Ref}{$Loop} ) && ( $Printout ) );
  }
}

sub Create_Output {
   my $sths; my $sthp;

  my $DBInsert="INSERT INTO ODS_LANDING.cl.LAND_CALL_QUALITY ( CALL_ID, CALL_LEG, CALL_ATTRIBUTE, CALL_ATTRIBUTE_VALUE ) VALUES (?,?,?,?);";

  if ( ! $opt_D ) {
    # We can save time/effort and prepare the Insert early then substitude on the loop
    $sths = $dbhs->prepare($DBInsert) if ( $opt_S );
    $sthp = $dbhp->prepare($DBInsert) if ( $opt_P );
  }

  foreach $Loop (@Output) {

    my ($Var1,$Var2,$Var3,$Var4)=split(',', $Loop);

    $Var1 =~ s/^ +//; $Var1 =~ s/ +$//;
    $Var2 =~ s/^ +//; $Var2 =~ s/ +$//;
    $Var3 =~ s/^ +//; $Var3 =~ s/ +$//;
    $Var4 =~ s/^ +//; $Var4 =~ s/ +$//;
    next if (( $Var3 =~ /HASH/ ) || ( $Var3 =~ /ARRAY/ ));
    next if (( $Var4 =~ /HASH/ ) || ( $Var4 =~ /ARRAY/ ));
    next if ( ! $Var4 =~ /HASH/ );
 
    if ( ! $opt_D ) {
      print "Inserting into SIT.\n" if ( ( $opt_S ) && ( $Verbose ) );
      print "Executing execute($Var1,$Var2,$Var3,$Var4)\n" if ( ( $opt_S ) && ( $Verbose ) );
      $sths->execute($Var1,$Var2,$Var3,$Var4) || die "Couldn't execute statement: ".$sths->errstr." on $Loop\n" if ( $opt_S );
      print "Inserting into DEV.\n" if ( ( $opt_P ) && ( $Verbose ) );
      print "Executing execute($Var1,$Var2,$Var3,$Var4)\n" if ( ( $opt_P ) && ( $Verbose ) );
      $sthp->execute($Var1,$Var2,$Var3,$Var4) || die "Couldn't execute statement: ".$sthp->errstr." on $Loop\n" if ( $opt_P );
    } else {
      print "Executing execute($Var1,$Var2,$Var3,$Var4)\n";
    }
  }
}


sub signal_handler {
    die "Caught a signal $!.\n";
    exit 0;
}


sub Create_SIT_DB_Connection {

  # Function:     dbh_connect
  # Description:  Creates a connection to a database
  # Arguments:    none
  # Returns:      $db_conn - database connection handle
  #
  my ($dbhs);
  # DB Info
  my $dbuser="NETOPS_USR_RO";
  my $dbpasswd="Up5!w0N#";
  my $Database="ODS_Landing";
  my $Port="1433";

  # SIT
  my $Target="SIT";
  my $Host="10.1.100.190";


  #
  # Manual Test:
  #  https://sites.google.com/site/fagonas/li/small-things
  #  /usr/local/sqsh/bin/sqsh -SSIT -U NETOPS_USR_RO -PUp5!w0N#
  # 
  # Truncate the table:
  #  isql -v SIT NETOPS_USR_RO Up5!w0N#
  #  TRUNCATE TABLE ODS_LANDING.cl.LAND_CALL_QUALITY
  #
  my $dsn="dbi:ODBC:DRIVER={FreeTDS};Server=$Host;Port=1433;Database=$Database";
  $dbhs =DBI->connect( "$dsn;UID=$dbuser;PWD=$dbpasswd;{ PrintError => 1, AutoCommit => 0 }" ) || die "Couldn't connect to Database: " . DBI->errstr;
    
  if (! defined($dbhs) ) {
    print "Error connecting to DSN '$Database'\n";
    print "Error was:\n";
    print "$DBI::errstr\n";         # $DBI::errstr is the error received from the SQL server
    exit 0;
  }
    
  return $dbhs;
}    


sub Create_PROD_DB_Connection {

  # Function:     dbh_connect
  # Description:  Creates a connection to a database
  # Arguments:    none
  # Returns:      $db_conn - database connection handle
  #
  my ($dbhp);
  # DB Info
  my $dbuser="NETOPS_USR_RO";
  my $dbpasswd="Up5!w0N#";
  my $Database="ODS_Landing";
  my $Port="1433";

  # Prod
  my $Target="PROD";
  my $Host="10.241.4.64";

  #
  # Manual Test:
  #  https://sites.google.com/site/fagonas/li/small-things
  #  /usr/local/sqsh/bin/sqsh -SSIT -U NETOPS_USR_RO -PUp5!w0N#
  # 
  # Truncate the table:
  #  isql -v SIT NETOPS_USR_RO Up5!w0N#
  #  TRUNCATE TABLE ODS_LANDING.cl.LAND_CALL_QUALITY
  #
  my $dsn="dbi:ODBC:DRIVER={FreeTDS};Server=$Host;Port=1433;Database=$Database";
  $dbhp =DBI->connect( "$dsn;UID=$dbuser;PWD=$dbpasswd;{ PrintError => 1, AutoCommit => 0 }" ) || die "Couldn't connect to Database: " . DBI->errstr;
    
  if (! defined($dbhp) ) {
    print "Error connecting to DSN '$Database'\n";
    print "Error was:\n";
    print "$DBI::errstr\n";         # $DBI::errstr is the error received from the SQL server
    exit 0;
  }
    
  return $dbhp;
}    

