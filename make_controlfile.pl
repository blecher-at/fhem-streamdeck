
#use strict;
use POSIX;

foreach (@ARGV)
{
	my $file = $_;

	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($file);
	my @line_parts = ();
	push @line_parts, "UPD";
	push @line_parts, POSIX::strftime("%Y-%d-%m", localtime( $mtime )) . "_" . POSIX::strftime("%H:%M:%S", localtime( $mtime ));
	push @line_parts, $size;
	push @line_parts, $file;
	
	print join(" ",@line_parts)."\n";
}