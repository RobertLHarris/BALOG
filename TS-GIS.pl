#!/usr/bin/perl -w

use strict;

my $Continue; my $Input;
my $Tail;
my $Date;
my $Len;
my $Target;

my $User=$ENV{"LOGNAME"};




while( ! $Continue ) {
  print "What Tail do you want to process?\n";
  print "-> ";
  $Tail=<>;
  chomp($Tail);

  if ( $Tail !~ /^\d\d\d\d\d$/ ) {
    print "Invalid Tail.  Please try again.\n";
    print "\n";
  } else {
    print "Processing Tail:  $Tail\n";
    print "  Is this the one you want (Y/N)\n";
    print "-> ";
    $Input=<>;
    chomp($Input);
    $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
  }
}


print "\n";
$Continue=0;
while( ! $Continue ) {
  print "What Date do you want to process? ( Use the date format YYYYMMDD )\n";
  print "-> ";
  $Date=<>;
  chomp($Date);
  $Date =~ s/\///g;

  if ( $Date !~ /^\d\d\d\d\d\d\d\d$/ ) {
    print "Invalid Date.  Please try again.\n";
    print "\n";
  } else {
    print "Starting Date: $Date.\n";
    print "  Is this the one you want (Y/N)\n";
    print "-> ";
    $Input=<>;
    chomp($Input);
    $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
  }
}


print "\n";
$Continue=0;
while( ! $Continue ) {
  print "How many days of flights do you want to process? \n";
  print "-> ";
  $Len=<>;
  chomp($Len);

  print "Processing a duration of $Len\n";
  print "  Is this what you want? (Y/N) \n";
  print "-> ";
  $Input=<>;
  chomp($Input);

  $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
}



$Target="/tmp/GIS-".$User."-".$Tail.".kml";

print "\n";
print "Executing:\n";
print "  /usr/bin/curl --data-urlencode \"tail=$Tail\" --data-urlencode \"date=$Date\" --data-urlencode \"days=$Len\" -d \"Submit=Submit\" http://performance.aircell.prod/reports/gis/ > $Target\n";
print "\n";
print "  *** This might take a few minutes!\n";
system("/usr/bin/curl --data-urlencode \"tail=$Tail\" --data-urlencode \"date=$Date\" --data-urlencode \"days=$Len\" -d \"Submit=Submit\" http://performance.aircell.prod/reports/gis/ > $Target");
print "\n";


print "\n\n";
print "Your GIS file should be $Target, please retrieve it from balog01 using winscp to your local machien for processing.\n";
print "\n\n";

exit 0;

















