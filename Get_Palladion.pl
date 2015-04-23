#!/usr/bin/perl -w

use LWP::Simple;
use JSON qw( decode_json );
use Data::Dumper;
use strict;

my $TargetDate=`/bin/date --date="yesterday" +%Y-%m-%d`;  chomp( $TargetDate );
# admin:oracle http://10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00
my $User="admin:oracle";
my $TargetEx="http://$User\@10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00";
my $TargetBase="http://10.240.21.100/r/calls";
my $TargetStart="$TargetDate+00:00:00";
my $TargetStop="$TargetDate+23:59:59";
my $Target=$TargetBase."/".$TargetStart."/".$TargetStop;
my $JSON;

print "\$Target :$Target:\n";

# Works
#/usr/bin/curl -k -L --digest --user admin:oracle http://10.240.21.100/r/calls/2015-03-16+00:00:00/2015-03-16+23:55:00
print "/usr/bin/curl -k -L --digest --user $User $Target\n";
open(INPUT, "/usr/bin/curl -k -L --digest -s --user $User $Target |");
while(<INPUT>) {
  chomp;
  $JSON=$_;
}
#$JSON=get( $Target ); die "Could not get $Target!" unless defined $JSON;

#my @Keys = @{ $JSON->{'data'} };
#foreach my $Loop ( @Keys ) {
#  print $Loop->{"name"} . "\n";
#}

# Decode the entire JSON
my $decoded_json = decode_json( $JSON );

# you'll get this (it'll print out); comment this when done.
print Dumper $decoded_json;

# Access the shares like this:
print "Data: ",
       #$decoded_json->{"$Target"}{'data'},
             "\n";

my @data = @{ $decoded_json->{'rpid'} };
foreach my $d ( @data ) {
  print $d->{"key"} . "\n";
}
