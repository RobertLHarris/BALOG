#!/usr/bin/perl -w

$|=1;

use strict;
use LWP::Simple;
use JSON qw( decode_json );
use XML::Simple;
use Data::Dumper;
use Scalar::Util qw/reftype/;

# Get yesterday's data
my $TargetDate=`/bin/date --date="yesterday" +%Y-%m-%d`;  chomp( $TargetDate );
# Get a specific date
my @TargetDates=( "2015-05-01", "2015-05-02", "2015-05-03", "2015-05-04", "2015-05-05", "2015-05-06", "2015-05-07", "2015-05-08", "2015-05-09",
		  "2015-05-10", "2015-05-11", "2015-05-12", "2015-05-13", "2015-05-14", "2015-05-15", "2015-05-16", "2015-05-17", "2015-05-18", "2015-05-19",
		  "2015-05-20", "2015-05-21", "2015-05-22", "2015-05-23", "2015-05-24", "2015-05-25", "2015-05-26", "2015-05-27", "2015-05-28", "2015-05-29",
		  "2015-05-30", "2015-05-30", "2015-05-31",
		  "2015-06-01", "2015-06-02", "2015-06-03", "2015-06-04", "2015-06-05", "2015-06-06", "2015-06-07", "2015-06-08" );

# Example URL Info
# admin:oracle http://10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00
my $JSONString;
my $Call;
my %Calls;
my $Counter=0;
my $Key;
my $Leg;
my $Verbose=0;
my $Testing=0;
my $Printout=1;

# Target Ends
#  /vq - Voice Quality
#  /messages - SIP Messages
#  /r/users/<userid>/calls - Calls belonging to the given platform user. The format of this resource is exactly like the format of the /r/calls resource.
#  /r/counters - The list of counters for the admin user and the `ALL' realm. 
#  /r/counters/<id> A representation of the given counter. 

foreach $TargetDate ( @TargetDates ) {
  print "Pulling Data for $TargetDate.\n";
  foreach my $Hour ( 0..23 ) {
    &Get_Calls($Hour);
  }
}

exit 0;

#
sub Get_Calls {
  my $Hour=$_[0];
  $Hour=substr("0".$Hour, -2);

  my $User="admin:oracle";
  my $TargetBase="http://10.240.21.100/r/calls";
  my $TargetStart="$TargetDate+".$Hour.":00:00";
  my $TargetStop="$TargetDate+".$Hour.":59:59";
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
    print "Main Call :$Call:\n" if ( $Verbose );
    $Leg=0;

    # Call Details is the key for the part ( i.e. setup_time )
    foreach my $CallDetails ( keys( %{$Loop} ) ) {
      next unless ( ${$Loop}{$CallDetails} );
      $Key=$Call.".".$Leg.".".$CallDetails;
      print "$Key : ${$Loop}{$CallDetails}\n" if ( $Printout );
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

  foreach my $VQ ( keys( %{$SRC} ) ) {
    if ( ${$SRC}{$VQ} ) {
      print "\${$SRC}{$VQ} :${$SRC}{$VQ}:\n" if ( $Verbose );
      &Process_Value( $Call, ${$SRC}{$VQ} );
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


  my $Converter = new JSON;
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONString=$_;
    
    print "\$JSONString :$JSONString:\n" if ( $Verbose );
  }

  my $SRC = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString) || die "Can't decode $JSONString :$!:\n";
  my $DATA=${$SRC}{data};
  print Dumper $DATA if ( $Verbose );

  foreach my $Loop ( @{$DATA} ) {
    # Call Details is the key for the part ( i.e. setup_time )
    foreach my $CallVQ ( keys( %{$Loop} ) ) {
      my $Direction=${$Loop}{direction};
      my $Value;
      $Direction="Unknown" if ( ! $Direction );
      if ( $CallVQ ne "data" ) {
        next unless ( ${$Loop}{$CallVQ} );
        $Key=$Call.".".$Leg.".".$Direction."-".$CallVQ;
        print "$Key : ${$Loop}{$CallVQ}\n" if ( $Printout );
      } else {
        $Key=$Call.".".$Leg.".".$Direction."-moscque_avg";
        $Value=${$Loop}{data}{moscqe_avg}; $Value="Unknown" if ( ! $Value );
        print "$Key : $Value\n";
        $Key=$Call.".".$Leg.".".$Direction."-packets_lost";
        $Value=${$Loop}{data}{packets_lost}; $Value="Unknown" if ( ! $Value );
        print "$Key : $Value\n";
        $Key=$Call.".".$Leg.".".$Direction."-jitter_max";
        $Value=${$Loop}{data}{jitter_max}; $Value="Unknown" if ( ! $Value );
        print "$Key : $Value\n";
        $Key=$Call.".".$Leg.".".$Direction."-jitter_avg";
        $Value=${$Loop}{data}{jitter_avg}; $Value="Unknown" if ( ! $Value );
        print "$Key : $Value\n";
        $Key=$Call.".".$Leg.".".$Direction."-packets_received";
        $Value=${$Loop}{data}{packets_received}; $Value="Unknown" if ( ! $Value );
        print "$Key : $Value\n";
        $Key=$Call.".".$Leg.".".$Direction."-r_factor";
        $Value=${$Loop}{data}{r_factor}; $Value="Unknown" if ( ! $Value );
        print "$Key : $Value";
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
    print "VQ $Ref\n" if ( $Verbose );
  } elsif ( $RefType eq "HASH" ) {
    print "Found $RefType at $Ref\n" if ( $Verbose );
    &Walk_Hash( $Call, $Ref);
  } elsif ( $RefType eq "ARRAY" ) {
    print "Found $RefType at $Ref\n" if ( $Verbose );
    &Walk_Array( $Call, $Ref);
  }
}


sub Walk_Array {
  my $Call=$_[0];
  my $Ref=$_[1];

  print "  Processing Array $Ref\n" if ( $Verbose );
  foreach my $Loop ( @{$Ref} ) {
    print "  \$Loop :$Loop:\n" if ( $Verbose );
    &Process_Value( $Call, $Loop );
  }

}


sub Walk_Hash {
  my $Call=$_[0];
  my $Ref=$_[1];

  print "Hash 1\n" if ( $Verbose );
  print "  Processing Hash $Ref\n" if ( $Verbose );
  $Leg++ if ( ${$Ref}{"src_device_name"} );
  print " ** Leg $Leg\n" if ( $Verbose );
  foreach my $Loop ( keys ( %{$Ref} ) ) {
    $Key=$Call.".".$Leg.".".$Loop;
    next unless ( ${$Ref}{$Loop} );
    my $RefType = reftype ${$Ref}{$Loop};
    if ( ! $RefType ) {
      print "$Key : ${$Ref}{$Loop}\n" if ( $Printout );
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
  $Leg++ if ( ${$Ref}{"src_device_name"} );
  print " ** Leg $Leg\n" if ( $Verbose );
  foreach my $Loop ( keys ( %{$Ref} ) ) {
    $Key=$Call.".".$Leg.".".$Type.".".$Loop;
    print "$Key : ${$Ref}{$Loop}\n" if ( ( ${$Ref}{$Loop} ) && ( $Printout ) );
  }
}
