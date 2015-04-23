#!/usr/bin/perl -w
$! = 1;

my $Verbose=1;

my $FileOut="F";
my $Year=`date +%Y`; chomp( $Year );
my $Month=`date +%m`; chomp( $Month );
my $Subject; my @Errors; my $Loop; my @Found;
my $FirstError; my $LastError; my $Count;
my $Status="Undefined";;
my $UserInfo="/tmp/ba_users_info.csv";

#
#  Lets check the status of the Provisioning file
#
my $dev; my $ino; my $mode; my $nlink; my $uid; my $gid; my $rdev;
my $size; my  $atime; my $mtime; my $ctime; my $blksize; my $blocks;
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($UserInfo);




# How long should we look back
my $Days="24 hours ago";
#my $Days="48 hours ago";
# Use last modified time
my $Type="-newermt ";

#
# Who are we going to email?
#
my $Users="rharris\@aircell.com";
#my $Users="networkopsco\@aircell.com";
#my $Users="networkopsco\@aircell.com,techsupport-co\@aircell.com,twasinger\@aircell.com,cusrey\@aircell.com,mzable\@aircell.com,rhamrin\@gogoair.com";

#
# Lets get our list of tails to check on
#
chdir( "/opt/log/atg/$Year/$Month" );
#open(TAILS, "ls -1 | sort | grep ^10[0123] |");
#open(TAILS, "ls -1 | sort | grep ^138 |");
open(TAILS, "ls -1 | sort |");
while(<TAILS>) {
  chomp;
  push(@TAILS, $_);
}

my $Date=`date`; chomp( $Date );
my $MaxDiff="1200";
my $StatusString = "User Info File was last modified ".  localtime( $mtime );
push(@Errors, "" );
push(@Errors, "Current Date: $Date" );
push(@Errors, $StatusString );
push(@Errors, "  * If this file is more than 1.5 hours ago, something is wrong.");
push(@Errors, "" );

#
# Lets look for the Auth errors for our tails
#
foreach $Loop (@TAILS) {
  $FirstError="";
  $Count=0;
  print "Processing $Loop\n" if ( $Verbose );
  my $FindCMD= "/bin/find $Loop -type f -iname $Loop*console*gz $Type \"$Days\" -exec /usr/local/bin/Check_Provisioning.pl \{\} \\; \n";
  print "\$FindCMD :$FindCMD:\n";
  open(INPUT, "$FindCMD |");
  while(<INPUT>) {
    chomp;
    print "\$_ :$_:\n" if ( $Verbose );
    $Count++;
    $FirstError=$_ if ( $FirstError eq "" );
    $LastError=$_;
  }
  if ( $FirstError ne "" ) {
    print "Found Problems with $Loop in $Count Log Files\n" if ( $Verbose );
    print  "  First Error was: $FirstError\n" if ( $Verbose );
    print  "  Last Error was: $LastError\n" if ( $Verbose );
    push(@Errors, "Found Problems with $Loop in $Count Log Files");
    push(@Errors, "  First Error was: $FirstError");
    push(@Errors, "  Last Error was: $LastError");
    push(@Errors, "  ** Provisioning Status :");
    open(STATUS, "/usr/local/bin/Check_Tail_Provisioning.pl -T $Loop -s  |");
    while(<STATUS>) {
      chomp;
      next if ( /out of date/ );
      push(@Errors, "  $_");
    }

    push(@Errors, "");
  }

  if ( ! grep( /SUSPENDED/, @Errors ) ) {
    push(@FinalErrors, @Errors);
    undef(@Errors);
  } else {
    undef(@Errors);
  }

}


#
# Here we actually send our mail/save logs
#
if ( $#FinalErrors < 0 ) {
  $Subject="Provisioning Check found no new issues.\n";
  open(MAILME, "| mailx -s \"$Subject\" $Users");
  print "No Errors found.\n" if ( $Verbose );
  print MAILME "No Errors found.\n";

  if ( $FileOut eq "T" ) {
    open(SAVEME, ">/tmp/ProvCheck.txt");
    print SAVEME "No Errors found.\n";
    close(SAVEME);
  } 
  exit 0;
} else {
  print "Sending mail with errors.\n" if ( $Verbose );
  $Subject="Provisioning Check for last $Days days in $Year/$Month";
  open(MAILME, "| mailx -s \"$Subject\" $Users");
  print MAILME "\n";
  print MAILME "Provisioning Errors found on the following Tails in the last $Days days.\n";
  print MAILME "\n";
  print MAILME "** Check Service Activation/Suspended First **\n";
  print MAILME "\n";
  foreach $Loop (@FinalErrors) {
    print MAILME "  $Loop\n";
  }
  print MAILME "\n";



  if ( $FileOut eq "T" ) {
    open(SAVEME, ">/tmp/ProvCheck.txt");
    print SAVEME "\n";
    print SAVEME "Provisioning Errors found on the following Tails in the last $Days days.\n";
    print SAVEME "\n";
    print SAVEME "** Check Service Activation/Suspended First **\n";
    print SAVEME "\n";
    print SAVEME "\n";
    foreach $Loop (@FinalErrors) {
      print SAVEME "  $Loop\n";
    }
    print SAVEME "\n";
    close(SAVEME);
  } 


}
close(MAILME);

