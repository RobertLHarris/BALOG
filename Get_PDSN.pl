#!/usr/bin/perl

use strict;
use warnings;

#use HTML::Parser;
package HTMLStrip;
use base "HTML::Parser";
#use LWP::Simple;

# GetOpt
use vars qw( $opt_h $opt_v $opt_T );
use Getopt::Mixed;
Getopt::Mixed::getOptions("h v T=s ");

my $Verbose=$opt_v;
my $Target=$opt_T;

if ( ! $Target ) {
  print "\n";
  print "Missing -T <Tail>\n";
  print "\n";
}

my @Tail;
my $Line;

#my $Source="http://skynet.gogoair.com/tails/info/allTails.php";
my $Source="http://10.241.1.92/tails/info/allTails.php";

my $p = new HTMLStrip;
open(INPUT, "wget -q -O - $Source |");
while(<INPUT>) {
  chomp;
  print "\$_ :$_:\n" if ( $Verbose );
  $_ =~ s/^\s+//g;
  $_ =~ s,\<td\>\</td\>,\<td> \</td\>,;
  if ( /\<tr\>/ ) {
    my $Line=join(',', @Tail);
    $Line =~ s/^\s+/ /g;
    next if ( ! $Line );
    next if ( $Line =~ /^#/ );
    if ( $Tail[0] eq "$Target" ) {
      print "PDSN Information for Tail: $Tail[0]\n";
      print "  IP: $Tail[1]\n";
      print "  Airline Code: $Tail[2]\n";
      print "  Provisioned Date: $Tail[3]\n";
      print "  IMSI: $Tail[4]\n";
      print "  MDN: $Tail[5]\n";
      print "  ESN: $Tail[6]\n";
    }
    undef($Line);
    undef(@Tail);
  }
  $p->parse($_) if ( /\<td\>/ );
}
$p->eof;

sub text {
  my ($self, $text) = @_;
  push( @Tail, $text );
  print ":$text:\n" if ( $Verbose );
}
