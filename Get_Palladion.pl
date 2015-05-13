#!/usr/bin/perl -w

use LWP::Simple;
use JSON qw( decode_json );
use Data::Dumper;
use strict;

my $TargetDate=`/bin/date --date="yesterday" +%Y-%m-%d`;  chomp( $TargetDate );
# admin:oracle http://10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00
my $User="admin:oracle";
#my $TargetEx="http://$User\@10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00";
my $TargetBase="http://10.240.21.100/r/calls";
my $TargetStart="$TargetDate+00:00:00";
my $TargetStop="$TargetDate+23:59:59";
my $Target=$TargetBase."/".$TargetStart."/".$TargetStop;
my $JSONOUT;
my $Call;
my %Calls;
my $Counter=0;
my $MainCounter=0;
my $Key;

# Target Ends
#  /vq - Voice Quality
#  /messages - SIP Messages
#  /r/users/<userid>/calls - Calls belonging to the given platform user. The format of this resource is exactly like the format of the /r/calls resource.
#  /r/counters - The list of counters for the admin user and the `ALL' realm. 
#  /r/counters/<id> A representation of the given counter. 

# Works

&Get_Calls;

exit 0;

#
sub Get_Calls {
  my $JSON = new JSON;
  print "Getting json $Target\n";
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONOUT=$_;
  }
#print Dumper $JSONOUT."\n";

  my $json_text = $JSON->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONOUT);
  

  $MainCounter="000";
  # Loop through the total call list
  foreach my $Loop (  @{$json_text->{data}} ) {
    my %Loop2=%{$Loop};

    # Loop through the individual keys in this call
    foreach my $Loop2 ( keys ( %{$Loop} ) ) {
#      print "  \$Loop2{$Loop2} :$Loop2{$Loop2}:\n";
      $Key="$MainCounter"."-"."$Loop2";
#      $Calls{"$MainCounter-$Loop2"}=$Loop2{$Loop2} if ( $Loop2{$Loop2} );
      $Calls{"$Key"}=$Loop2{$Loop2} if ( $Loop2{$Loop2} );
    }

    $Key="$MainCounter"."-code";
    if ( $Calls{"$Key"} != "603" ) {
      print "Lookign Deeper.\n";
      $Key="$MainCounter"."-url";
      &Get_Call_VQ($Calls{"$MainCounter-url"});
    } else {
      next;
    }

#   while (my($k, $v) = each( %Calls ) ){
#     print "$k => $v\n";
#   }
    foreach my $PLoop ( sort ( keys %Calls ) ) {
      if ( $PLoop =~ /^\d\d\d\d+-/ ) {
        print "  $PLoop $Calls{$PLoop}\n";
      } else {
        print "$PLoop $Calls{$PLoop}\n";
      }
    }

    print "\n";
    %Calls = ();

    $MainCounter++;
    $MainCounter=substr("00".$MainCounter, -3);
    exit 0;
  }
}

sub Get_Call_Details {
  my $TargetURL=$_[0];
  my $TargetBase="http://10.240.21.100";
  my $Target=$TargetBase.$TargetURL;
  my $JSONOUT;

  my $JSON = new JSON;

  print "Getting json $Target\n";
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONOUT=$_;
  }

  my $json_text = $JSON->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONOUT);
 
  my @Keys=keys %{ $json_text };
#  foreach my $Loop ( @Keys ) {
#    print "\${\$json_text}{$Loop} :${$json_text}{$Loop}:\n";
#  }
}


sub Get_Call_VQ {
  my $TargetURL=$_[0];
  my $TargetBase="http://10.240.21.100";
  my $Target=$TargetBase.$TargetURL."/vq";
  my $JSONOUT;
  
  my $JSON = new JSON;

  print "Getting VQ json $Target\n";
  open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
  while(<INPUT>) {
    chomp;
    $JSONOUT=$_;
  }

  my $json_text = $JSON->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($JSONOUT);

  $Counter=1;
  foreach my $Loop ( @{$json_text->{data}} ) {
    my %Loop2=%{$Loop};
    foreach my $Loop2 ( keys ( %{$Loop} ) ) {
#      $Calls{"$MainCounter-$Counter-$Loop2"}=$Loop2{$Loop2} if ( $Loop2{$Loop2} );
      $Calls{"$MainCounter$Counter-$Loop2"}=$Loop2{$Loop2} if ( $Loop2{$Loop2} );
    }

    &Get_Call_VQ_Details($Loop2{"data"}) if ( $Loop2{"data"} );
    $Counter++;
  }
}


sub Get_Call_VQ_Details {

  my $Ref=$_[0];

#print Dumper $Ref;
  
  my %Loop2=%{$Ref};
  foreach my $Loop2 ( sort ( keys ( %{$Ref} ) ) ) {
#    print "  \$Loop2{$Loop2} :$Loop2{$Loop2}:\n";
#    $Calls{"$MainCounter-$Counter-$Loop2"}=$Loop2{$Loop2} if ( $Loop2{$Loop2} );
    $Calls{"$MainCounter$Counter-$Loop2"}=$Loop2{$Loop2} if ( $Loop2{$Loop2} );
  }
}
