#!/usr/bin/perl -w

use strict;

# GetOpt
use vars qw( $opt_v $opt_T );
use Getopt::Mixed;
Getopt::Mixed::getOptions("v T=s");


my @SCE=&Define_SCE_Ranges;
my $Loop;
my $SCE;

# Define Outputs
my $SCEBlock="Not Found";
my $SCEIPRange="Not Found";
my $SCETemplate="Not Found";
my $SCESize="99999999999";

my $Verbose=$opt_v;
my $IP=$opt_T;

print "Checking $IP\n";
#my $IPInt=unpack N => pack CCCC => split /\./ => $IP;
my $IPInt=&IP2Dec( $IP );

print "IPInt :$IPInt:\n";

foreach $Loop ( 0..$#SCE ) {
  my $Size;
  my $Min; my $MinInt;
  my $Max; my $MaxInt;

#  print "\$SCE[$Loop] :$SCE[$Loop]:\n";
  print "\$SCE[$Loop] :$SCE[$Loop]:\n" if ( $Verbose );
  my ( @Block )=split('\s+', $SCE[$Loop]);

  my $BlockName=$Block[3];
  my $IPRange=$Block[5];
  my $Template=$Block[7];
  print "Block Name: $BlockName\n" if ( $Verbose );
  print "IP Range: $IPRange\n" if ( $Verbose );
    $IPRange =~ s,:, ,g;
  print "Template : $Template\n" if ( $Verbose );


  next if ( $IPRange =~ /0xffffffff/);

  my $Skip=0; 
  my $NetInfo="/usr/local/bin/ipcalc.pl -n $IPRange";
  print "\$NetInfo :$NetInfo:\n" if ( $Verbose );
  open(INPUT, "$NetInfo |");
  while(<INPUT>) {
    chomp;
    print "\$_ :$_:\n" if ( $Verbose );

    # Low Point
    if ( /Netmask:/ ) {
      print "NetMask(Range) : $_\n" if ( $Verbose );
      ( undef, undef, undef, $Size )=split(" ", $_);
      print "\$Size :$Size:\n" if ( $Verbose );
    }
    if ( /HostMin:/ ) {
      print "HostMin : $_\n" if ( $Verbose );
      ( undef, $Min )=split(" ", $_);
      print "\$Min :$Min:\n" if ( $Verbose );
      $MinInt=&IP2Dec( $Min );
      print "\$MinInt :$MinInt:\n" if ( $Verbose );
    }
    # High Point
    if ( /HostMax:/ ) {
      print "HostMax : $_\n" if ( $Verbose );
      ( undef, $Max )=split(" ", $_);
      print "\$Max :$Max:\n" if ( $Verbose );
      $MaxInt=&IP2Dec( $Max );
      print "\$MaxInt :$MaxInt:\n" if ( $Verbose );
    }
  }

  if ( ( ( $IPInt <= $MaxInt ) && ( $IPInt >= $MinInt )) && ( $SCESize > $Size )) {
    $SCEBlock=$BlockName;
    $SCEIPRange=$IPRange;
    $SCETemplate=$Template;
    $SCESize=$Size;
  }
}

print "SCE Policy Designation: $SCEBlock\n";
print "SCE IP Block: $SCEIPRange\n";
print "SCE Template: $SCETemplate\n";

###################
# Subs Below Here #
###################
sub IP2Dec {
  my $Int=unpack N => pack CCCC => split /\./ => $_[0];

  return( $Int );
}

sub Define_SCE_Ranges {
	#my @SCE = qw(
	my @SCE = (
	"subscriber anonymous-group name \"LT4\" IP-range 10.30.94.0:0xffffff00 template 4",
	"subscriber anonymous-group name \"N74JA_3\" IP-range 10.16.66.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"LT12\" IP-range 10.30.51.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"Business_Aviation\" IP-range 10.112.0.0:0xfff00000 template 2",
	"subscriber anonymous-group name \"Boeing_10081\" IP-range 10.112.86.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"Boeing_10038\" IP-range 10.112.31.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"Boeing_10060\" IP-range 10.112.55.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"Boeing_10154\" IP-range 10.112.160.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"Boeing_10641\" IP-range 10.114.120.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"Boeing_11750\" IP-range 10.119.46.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"BA_Lite\" IP-range 10.127.0.0:0xffff0000 template 10",
	"subscriber anonymous-group name \"Boeing_12218\" IP-range 10.120.21.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"KU_LAB\" IP-range 10.79.0.0:0xffff0000 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-2\" IP-range 10.39.196.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-3\" IP-range 10.38.20.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-4\" IP-range 10.39.230.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-5\" IP-range 10.38.28.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-6\" IP-range 10.38.16.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-8\" IP-range 10.38.34.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-7\" IP-range 10.38.6.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02\" IP-range 10.240.77.22:0xffffffff template 5",
	"subscriber anonymous-group name \"DM5_1\" IP-range 10.47.2.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"DM5_2\" IP-range 10.47.3.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"KU_72_1\" IP-range 10.72.1.1:0xffffffff template 5",
	"subscriber anonymous-group name \"KU_72_2\" IP-range 10.72.1.2:0xffffffff template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-9\" IP-range 10.33.60.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-10\" IP-range 10.39.12.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-11\" IP-range 10.39.76.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"XS-02_TAILS-12\" IP-range 10.39.96.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"N74JA\" IP-range 10.47.0.0:0xfffffe00 template 5",
	"subscriber anonymous-group name \"ATG4_KU\" IP-range 10.48.0.0:0xfff00000 template 14",
	"subscriber anonymous-group name \"BA_Lite_Test\" IP-range 10.14.0.0:0xffffc000 template 10",
#	"subscriber anonymous-group name \"BA Standard_Test\" IP-range 10.14.64.0:0xffffc000 template 2",
	"subscriber anonymous-group name \"LT34\" IP-range 10.30.112.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"BA_High_Perf\" IP-range 10.122.111.0:0xffffff00 template 18",
	"subscriber anonymous-group name \"ATG_13409\" IP-range 10.122.219.0:0xffffff00 template 17 ",
	"subscriber anonymous-group name \"NG7\" IP-range 10.30.107.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"NG9\" IP-range 10.30.111.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"BA_Standard\" IP-range 10.112.216.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"Business_Aviation_2\" IP-range 10.128.0.0:0xfff00000 template 17",
	"subscriber anonymous-group name \"BA_High_Performance\" IP-range 10.128.0.0:0xfffc0000 template 18",
	"subscriber anonymous-group name \"BA_Lite_2\" IP-range 10.132.0.0:0xfffe0000 template 10",
	"subscriber anonymous-group name \"SBBI-GGTT-High_P\" IP-range 10.15.0.0:0xfffffe00 template 8",
	"subscriber anonymous-group name \"SBBI-GGTT-Balanc\" IP-range 10.15.2.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"SBBI-GGTT-Conser\" IP-range 10.15.3.0:0xffffff00 template 10",
	"subscriber anonymous-group name \"SBBI-N-GGTT-High_P\" IP-range 10.15.4.0:0xfffffe00 template 8",
	"subscriber anonymous-group name \"SBBI-N-GGTT-Balanc\" IP-range 10.15.6.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"SBBI-N-GGTT-Conser\" IP-range 10.15.7.0:0xffffff00 template 10",
	"subscriber anonymous-group name \"12487\" IP-range 10.120.105.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"12697\" IP-range 10.121.193.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"13281\" IP-range 10.122.160.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"11198\" IP-range 10.116.197.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"12504\" IP-range 10.120.108.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"PLT\" IP-range 10.30.53.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"14606\" IP-range 10.125.132.0:0xffffff00 template 17",
	"subscriber anonymous-group name \"United_ATG\" IP-range 10.28.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"United_ATG4\" IP-range 10.44.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"AAL_ATG1\" IP-range 10.16.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"AAL_ATG2\" IP-range 10.17.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"AAL_ATG3\" IP-range 10.21.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"AAL_ATG4_1\" IP-range 10.32.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"AAL_ATG4_2\" IP-range 10.33.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"AAL_ATG4_3\" IP-range 10.37.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"Boeing_12219\" IP-range 10.120.27.0:0xffffff00 template 9",
	"subscriber anonymous-group name \"DM1_1\" IP-range 10.47.98.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"DM1_2\" IP-range 10.47.99.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"CA_Control\" IP-range 10.16.0.0:0xfff00000 template 20",
	"subscriber anonymous-group name \"RDP_Server\" IP-range 10.240.15.200:0xffffffff template 20",
	"subscriber anonymous-group name \"LT10\" IP-range 10.30.110.0:0xffffff00 template 20",
	"subscriber anonymous-group name \"TM\" IP-range 10.244.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"ATG4\" IP-range 10.32.0.0:0xfff00000 template 20",
	"subscriber anonymous-group name \"XS-03\" IP-range 10.240.77.23:0xffffffff template 20     ",
	"subscriber anonymous-group name \"Virgin_ATG\" IP-range 10.22.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"Virgin_ATG4\" IP-range 10.38.0.0:0xffff0000 template 20",
	"subscriber anonymous-group name \"VNA_Load_Test\" IP-range 10.64.1.0:0xffffff00 template 22",
	"subscriber anonymous-group name \"HC5\" IP-range 10.79.203.0:0xffffff00 template 22",
	"subscriber anonymous-group name \"Vietnam\" IP-range 10.64.16.0:0xfffff000 template 20",
	"subscriber anonymous-group name \"BA_ATG4_Test\" IP-range 10.14.192.0:0xffffc000 template 17",
	"subscriber anonymous-group name \"N741JA_1\" IP-range 10.47.224.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"N741JA_2\" IP-range 10.47.225.0:0xffffff00 template 5",
	"subscriber anonymous-group name \"KU_All\" IP-range 10.72.0.0:0xfff80000 template 5",
	"subscriber anonymous-group name \"BA_ATG4_1\" IP-range 10.160.0.0:0xffff0000 template 17",
	"subscriber anonymous-group name \"BA_ATG4_2\" IP-range 10.161.0.0:0xffff0000 template 17"
	);
	return(@SCE);
}
	
	
