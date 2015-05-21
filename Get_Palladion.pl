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
#my $TargetDate="2015-05-19";

# Example URL Info
# admin:oracle http://10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00
my $JSONString;
my $Call;
my %Calls;
my $Counter=0;
my $Key;
my $Leg;
my $Verbose=0;

# Target Ends
#  /vq - Voice Quality
#  /messages - SIP Messages
#  /r/users/<userid>/calls - Calls belonging to the given platform user. The format of this resource is exactly like the format of the /r/calls resource.
#  /r/counters - The list of counters for the admin user and the `ALL' realm. 
#  /r/counters/<id> A representation of the given counter. 

# Works

my $Hour=0;

foreach my $Hour ( 0..23 ) {
  &Get_Calls($Hour);
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

  print "Retrieving hour $Hour: $Target\n";

  my $Converter = new JSON;
  print "Getting json $Target\n";
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONString=$_;
  }


  #my $TopXML = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString);
  my $TopXML = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString) || die "Can't decode $JSONString :$!:\n";

  my $XMLOut = XMLout( $TopXML, SuppressEmpty => undef, KeyAttr => { data => 'call_id'} );
  my $XML = XMLin( $XMLOut, SuppressEmpty => undef, KeyAttr => { data => 'call_id'} );

  foreach $Call ( keys( %{$XML->{data}} ) ) {
    print "Main Call :$Call:\n" if ( $Verbose );
    my $Leg=0;

    # Call Details is the key for the part ( i.e. setup_time )
    foreach my $CallDetails ( keys( %{$XML->{data}->{$Call}} ) ) {
      next unless ( ${$XML->{data}->{$Call}}{$CallDetails} );
      $Key=$Call.".".$Leg.".".$CallDetails;
      print "$Key : ${$XML->{data}{$Call}}{$CallDetails}\n";
    }

    &Get_VQ( $Call, ${$XML->{data}->{$Call}}{"url"});
# This limits it to just the first call...
#exit 0;

  }
  
}



sub Get_VQ {
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

  my $TopXML = $Converter->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONString) || die "Can't decode $JSONString :$!:\n";

  my $XMLOut = XMLout( $TopXML, SuppressEmpty => undef, KeyAttr => { data => 'call_id'} );
  my $XML = XMLin( $XMLOut, SuppressEmpty => undef, KeyAttr => { data => 'call_id'} );

  print Dumper $XML if ( $Verbose );

  foreach my $VQ ( keys( %{$XML} ) ) {
    if ( ${$XML}{$VQ} ) {
      &Process_Value( $Call, ${$XML}{$VQ} );
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

  print "  Processing Hash $Ref\n" if ( $Verbose );
  $Leg++ if ( ${$Ref}{"src_device_name"} );
  print " ** Leg $Leg\n" if ( $Verbose );
  foreach my $Loop ( keys ( %{$Ref} ) ) {
    $Key=$Call.".".$Leg.".".$Loop;
    print "    $Key : ${$Ref}{$Loop}\n" if ( ${$Ref}{$Loop} );
  }
}
