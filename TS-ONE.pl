#!/usr/bin/perl -w

use strict;

my $Continue; my $Input;
my $Advanced; my $ONE_Options="";
my $Extract_Options="";
my $Logs=""; my $Tail;
my $Year; my $Mon; my $sDay; my $fDay; 

while( ! $Continue ) {
  print "Which type of log do you want to parse?\n";
  print "  1) All standard\n";
  print "  2) ATG Console\n";
  print "  3) ATG Messages\n";
  print "  4) ATG SM (Airlink)\n";
  print "  ...\n";
  print "  9) Done ( That's all folks )\n";
  print "  0) Clear\n";
  print "  ...\n";
  print " 99) Exit/Quit\n";
  print "-> ";
  $Input=<>;
  chomp($Input);

  if ( $Input == 1 ) {
    $Continue=1;
    $Logs.="--all ";
  }
  if ( $Input == 2 ) {
    $Continue=0;
    $Logs.="--console ";
    print "  Added --console\n";
  }
  if ( $Input == 3 ) {
    $Continue=0;
    $Logs.="--messages ";
    print "  Added --messages\n";
  }
  if ( $Input == 4 ) {
    $Continue=0;
    $Logs.="--airlink ";
    print "  Added --airlink\n";
  }
  if ( $Input == 9 ) {
    $Continue=0;
    print "Processing $Logs\n";
  }
  if ( $Input == 0 ) {
    $Continue=0;
    $Logs="";
    print "Reset\n";
  }
  if ( $Input == 99 ) {
    exit 0;
  }
}

print "\n";
$Continue=0;
while( ! $Continue ) {
  print "What Tail do you want to process?\n";
  print "-> ";
  $Tail=<>;
  chomp($Tail);

  if ( $Tail !~ /\d\d\d\d\d/ ) {
    print "Invalid Tail.  Please try again.\n";
    print "\n";
  } else {
    print "Processing $Tail, is this the one you want (Y/N)\n";
    print "-> ";
    $Input=<>;
    chomp($Input);
    $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
  }
}


print "\n";
$Continue=0;
my $Comp;
while( ! $Continue ) {
  $Comp="y";
  print "Do you want to compensate the time for ATG time drift?\n";
  print "  ( If you want to compare activity to the GIS map you probably want to say N, otherwise Y )\n";
  print "-> ";
  $Comp=<>;
  chomp($Comp);

  print "I am ";
  if (( $Comp eq "N" ) || ( $Comp eq "n" )) {
    print "NOT ";
  }
  print "going to compensate for ATG time drift.\n";
  print "Is this what you want?\n";
    
  print "-> ";
  $Input=<>;
  chomp($Input);

  $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
}

$Extract_Options=" --nocomp" if (( $Comp eq "N" ) || ( $Comp eq "n" ));

print "\n";
$Continue=0;
while( ! $Continue ) {
  print "What Year do you want to process? ( Use 4 digit year )\n";
  print "-> ";
  $Year=<>;
  chomp($Year);

  print "Processing $Year, is this the one you want (Y/N)\n";
  print "-> ";
  $Input=<>;
  chomp($Input);

  $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
}


print "\n";
$Continue=0;
while( ! $Continue ) {
  print "What Month do you want to process? ( Use 2 digit month )\n";
  print "-> ";
  $Mon=<>;
  chomp($Mon);

  print "Processing $Mon, is this the one you want (Y/N)\n";
  print "-> ";
  $Input=<>;
  chomp($Input);

  $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
}


print "\n";
$Continue=0;
while( ! $Continue ) {
  print "What is the first day you want to process? ( Use 2 digit day )\n";
  print "-> ";
  $sDay=<>;
  chomp($sDay);

  print "What is the last day you want to process? ( Use 2 digit day )\n";
  print "-> ";
  $fDay=<>;
  chomp($fDay);

  print "Processing from $sDay to $fDay, is this what you want (Y/N)\n";
  print "-> ";
  $Input=<>;
  chomp($Input);

  $Continue=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
}

print "\n";
print "Do you wish to include advanced options? (Y/N) \n";
print "  ( many of these are overly verbose ) \n";
print "-> ";
$Input=<>;
chomp($Input);

$Advanced=1 if (( $Input eq "Y" ) || ( $Input eq "y" ));
$Continue="0";
if ( $Advanced ) {
  while( ! $Continue ) {
    print "Which type of log do you want to parse?\n";
    print "  1) Temperature Logging\n";
    print "  2) Fan RPM Logging\n";
    print "  3) Authentication Logging\n";
    print "  4) Pings\n";
    print "  5) DHCP activity\n";
    print "  6) Devices Discovered\n";
    print "  ...\n";
    print "  9) Done ( That's all folks )\n";
    print "  0) Clear Options\n";
    print "-> ";
    $Input=<>;
    chomp($Input);
  
    if ( $Input == 1 ) {
      $Continue=0;
      $ONE_Options.="--temp ";
      print "  Added --temp\n\n";
    }
    if ( $Input == 2 ) {
      $Continue=0;
      $ONE_Options.="--fan ";
      print "  Added --fan\n\n";
    }
    if ( $Input == 3 ) {
      $Continue=0;
      $ONE_Options.="--auth ";
      print "  Added --auth\n\n";
    }
    if ( $Input == 4 ) {
      $Continue=0;
      $ONE_Options.="--pings ";
      print "  Added --pings\n\n";
    }
    if ( $Input == 5 ) {
      $Continue=0;
      $ONE_Options.="--dhcp ";
      print "  Added --dhcp\n\n";
    }
    if ( $Input == 6 ) {
      $Continue=0;
      $ONE_Options.="--devices ";
      print "  Added --devices\n\n";
    }
    if ( $Input == 9 ) {
      $Continue=1;
      print "  Time to run.\n\n";
    }
    if ( $Input == 0 ) {
      $Continue=0;
      $ONE_Options="";
      print "Reset\n\n";
    }
  }
}

print "\n";
$Continue=0;
while( ! $Continue ) {
  print "Do you want GGTT (Accuroam) Analysis?\n";
  print "-> ";
  $Input=<>;
  chomp($Input);

  if (( $Input eq "Y" ) || ( $Input eq "y" )) {
    print "\n";
    print "Which do you want:\n";
    print "  1) Short Analysis\n";
    print "  2) Long Analysis\n";
    print "  0) None ( Exit )\n";
    print "-> ";
    $Input=<>;
    chomp($Input);
 
    if ( $Input == 1 ) {
      $Continue=1;
      $ONE_Options="--SA ";
    } elsif ( $Input == 2 ) {
      $Continue=1;
      $ONE_Options="--Report ";
    } elsif ( $Input == 0 ) {
      $Continue=1;
    } else {
      $Continue=0;
    }
  } else {
    $Continue=1;
  }
}


$ONE_Options.=" --month $Mon --year $Year";
print "\n";
print "Executing:\n";
print "  *** This might take a while!\n";
print "  /usr/local/bin/Extract_ONE_Log.pl $Logs -T $Tail -y $Year -m $Mon --sd $sDay --fd $fDay $Extract_Options --so | /usr/local/bin/ONE.pl -f- --all $ONE_Options\n";
print "\n";
print "  *** This might take a while!\n";
print "\n";
system("/usr/local/bin/Extract_ONE_Log.pl $Logs -T $Tail -y $Year -m $Mon --sd $sDay --fd $fDay $Extract_Options --so | /usr/local/bin/ONE.pl -f- --all $ONE_Options");

exit 0;

















