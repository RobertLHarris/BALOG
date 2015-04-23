#!/usr/bin/perl -w

use strict;
use diagnostics;
my $dev; my $ino; my $mode; my $nlink; my $uid; my $gid; my $rdev; 
my $size; my  $atime; my $mtime; my $ctime; my $blksize; my $blocks;

my $Verbose=0;

my $Date=`/bin/date +%Y/%m/%d`; chomp( $Date );
#my $Address="rharris\@gogoair.com";
my $Address="techsupport-co\@aircell.com,networkopsco\@aircell.com,bacustomerservice\@gogoair.com";

#
my $TailPattern="BA_tailVerReport_20";
my $TailLink="/usr/local/bin/BATailVer/BA_tailVerReport.csv";
#
my $MissingPattern="BA_tailVerReport_Missing_Log_";
my $MissingLink="/usr/local/bin/BATailVer/BA_tailVerReport_Missing_Log.csv";

chdir("/usr/local/bin/BATailVer");

my $LatestMissing=&Check_File($MissingLink, $MissingPattern);
my $LatestReport=&Check_File($TailLink, $TailPattern);

system("cd /usr/local/bin/BATailVer; echo \"Attaching the reports as of $Date.\" | mailx -s \"BA Tail Reports as of $Date\" -a $LatestMissing -a $LatestReport $Address");

exit 0;


#############
# Sub Procs #
#############
sub Check_File {
  my $Target=$_[0];
  my $Pattern=$_[1];
  my $LatestFile;
  my $LatestCTime;
  my $LinkCTime;
  
  #ls -1 $Pattern* | sort
  # Get Latest File
  open(INPUT, "ls -1 $Pattern* | sort | tail -1 |");
  while(<INPUT>) {
    chomp;
    $LatestFile=$_;
    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($LatestFile);
    $LatestCTime=$ctime;
    print "$LatestFile was created at $LatestCTime.\n" if ( $Verbose );
  }
  ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($Target);
  $LinkCTime=$ctime;
  print "$Target was created at $LinkCTime.\n" if ( $Verbose );
  
#  if ( $LatestCTime > $LinkCTime ) {
#    print "There is a new file $LatestFile.  Updating the link.\n" if ( $Verbose );
    unlink($Target);
    symlink( "$LatestFile", "$Target" );
    print "Linked $LatestFile to $Target\n" if ( $Verbose );
#  } else {
#    print "There are no newer files than the last link.\n" if ( $Verbose );
#  }

  return( $LatestFile );
}
