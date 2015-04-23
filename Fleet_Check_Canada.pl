#!/usr/bin/perl -w

my $CSV="F";
my $Verbose="F";
my $FileOut="F";
my $FirstError; my $LastError; my $Count;
my %CanadaMessage;
my %CanadaMessageCSV;

my $Year=`date +%Y`; chomp( $Year );
my $Month=`date +%m`; chomp( $Month );
my $Subject; my @Errors; my $Loop; my @Found;
my $BasePath="/opt/log/atg/$Year/$Month";

# How long should we look back
# Use last modified time
my $Type="-mtime ";
# Use last changed time
#my $Type="-ctime ";

#my $Users="rharris\@aircell.com";
#my $Users="techsupport-co\@aircell.com,networkopsco\@aircell.com";
my $Users="networkopsco\@aircell.com";

chdir( $BasePath );
#open(TAILS, "ls -1 | sort |");
open(TAILS, "find $BasePath -type d -name sm | grep  1[0-9][0-9][0-9][0-9]/sm\$ |");
while(<TAILS>) {
  chomp;
  push(@TAILS, $_);
}

foreach $Loop (@TAILS) {
  $FirstError="";
  $Count=0;
  print "Processing $Loop\n" if ( $Verbose eq "T" );
  print "/bin/find $Loop -type f -iname \*SM.tar.gz -exec /usr/local/bin/Check_Canada.pl \{\} \\; \n" if ( $Verbose eq "T" );
  open(INPUT, "/bin/find $Loop -type f -iname \*SM.tar.gz -exec /usr/local/bin/Check_Canada.pl \{\} \\; |");
  while(<INPUT>) {
    chomp;
    ( undef, $Tail, undef, undef, undef, $Cell, undef )=split (' ', $_); 
    my $Counter=$Tail."-".$Cell;
    print "\$Tail :$Tail: \$Cell :$Cell:\n" if ( $Verbose eq "T" );
    $Canada{$Counter}=0 if ( ! $Canada{$Counter} );
    $Canada{$Counter}++;
    $CanadaMessage{$Counter}="$_";
    $CanadaMessageCSV{$Counter}="$Tail, $Cell";
    print "\$CanadaMessage{$Counter} :$CanadaMessage{$Counter}:\n" if ( $Verbose eq "T" );
    print "\$CanadaMessageCSV{$Counter} :$CanadaMessageCSV{$Counter}:\n" if ( $Verbose eq "T" );
  }
}

if ( scalar( keys ( %Canada ) ) > 0 ) {
  print "Sending mail with errors.\n" if ( $Verbose eq "T" );
  $Subject="Usage Check for tails using Canadian towers in the Month $Month ";
  open(MAILME, "| mailx -s \"$Subject\" $Users");
  print MAILME "\n";
  print MAILME "The following tails used the Canadian towers in Month $Month.\n";
  print MAILME "\n";
  print MAILME "Tail, Cell Site, Usage\n" if ( $CSV eq "T" );
  foreach $Loop ( sort ( keys ( %CanadaMessage ) ) ) {
    if ( $CSV eq "F" ) {
      print "$CanadaMessage{$Loop} $Canada{$Loop} times.\n" if ( $Verbose eq "T" );
      print MAILME "$CanadaMessage{$Loop} $Canada{$Loop} times.\n";
    } else {
      print "$CanadaMessageCSV{$Loop}, $Canada{$Loop}\n" if ( $Verbose eq "T" );
      print MAILME "$CanadaMessageCSV{$Loop}, $Canada{$Loop}\n";
    }
  }
  print MAILME "\n";
  print MAILME "To get the CSV version, edit /usr/local/bin/Fleet_Check_Canada.pl and set $CSV=\"T\" at the top then re-run.\n" if ( $CSV eq "F" );
  print MAILME "\n";

  if ( $FileOut eq "T" ) {
    open(SAVEME, ">/tmp/Canada_Check.txt");
    print SAVEME "\n";
    print SAVEME "The following tails used the Canadian towers in the Month $Month.\n";
    print SAVEME "\n";
    print SAVEME "Tail, Cell Site, Usage\n" if ( $CSV eq "T" );
    foreach $Loop ( sort ( keys ( %Canada ) ) ) {
      print SAVEME "$CanadaMessage{$Loop} $Canada{$Loop} times.\n";
    }
    print MAILME "\n";
    close(SAVEME);
  } 
} else {
  $Subject="Canada Usage Check found no tails using Canadian Cell Towers.\n";
  open(MAILME, "| mailx -s \"$Subject\" $Users");
  print "No Errors found.\n" if ( $Verbose eq "T" );
  print MAILME "No Canadian usage found.\n";

  if ( $FileOut eq "T" ) {
    open(SAVEME, ">/tmp/Canada_Check.txt");
    print SAVEME "No Canadian usage found.\n";
    close(SAVEME);
  } 
  exit 0;
}
close(MAILME);











