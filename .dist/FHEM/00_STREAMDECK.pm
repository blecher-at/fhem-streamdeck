#################################################################################
# 
# $Id: 00_STREAM_DECK $ 
#
# FHEM Module for Elgato Stream Deck
#
# Copyright (C) 2017 Stephan Blecher - www.blecher.at
# https://github.com/blecher-at/fhem-streamdeck
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
#
###########################
#package main;

use strict;
use warnings;
use GPUtils qw(:all);
use Image::Magick;
use DevIo;
use Fcntl ':flock'; 
use Digest::SHA qw(sha1_hex);

######################################################################################
sub STREAMDECK_Read($);
sub STREAMDECK_Ready($);
sub STREAMDECK_Parse($$);
sub STREAMDECK_CmdConfig($);
sub STREAMDECK_ReInit($);

sub STREAMDECK_Initialize($) {
  my ($hash) = @_;

  $hash->{ReadFn}  = "STREAMDECK_Read";
  $hash->{ReadyFn} = "STREAMDECK_Ready";
  $hash->{SetFn}   = "STREAMDECK_Set";
  $hash->{DefFn}   = "STREAMDECK_Define";
  $hash->{UndefFn} = "STREAMDECK_Undef";
  $hash->{AttrFn}  = "STREAMDECK_Attr";
  $hash->{StateFn} = "STREAMDECK_SetState";
  $hash->{ShutdownFn} = "STREAMDECK_Shutdown";
  $hash->{AttrList}  = "disable:0,1 brightness rotate ". $readingFnAttributes;
}

sub STREAMDECK_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
  	
	if (@a < 3) {
		my $msg = "wrong syntax: define <name> STEAMDECK <devicefile>";
		Log3 undef, 2, $msg;
		return $msg;
	}
	
	my $name = $a[0];
	my $dev = $a[2];

	$hash->{NAME} = $name;
	$hash->{file} = $dev;
	$hash->{DeviceName} = "$dev\@directio";
	$hash->{page} = "root";
	
	DevIo_CloseDev($hash);
	my $ret = DevIo_OpenDev($hash, 1, "STREAMDECK_DoInit");
	return $ret;
}

sub STREAMDECK_Undef($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	DevIo_CloseDev($hash);
	return undef;
}

sub STREAMDECK_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}


sub STREAMDECK_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $cmd = $a[1];
	
	my @sets = qw(on off toggle redraw);

	# create a list of pages set on keys
	my %pages = qw(root 1);
	GP_ForallClients($hash, sub {
		my $client = shift;
		$pages{AttrVal($client->{NAME}, 'page', 'root')} = 1;
	});
	
	my @uniqpages = keys %pages;
	
	return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', @sets).' page:'.join(',', @uniqpages) unless $cmd ~~ @sets or $cmd eq "page";

	STREAMDECK_Brightness_Toggle($hash) if($cmd eq "toggle");
	STREAMDECK_Brightness($hash, $attr{$name}{brightness}) if($cmd eq "on");
	STREAMDECK_Brightness($hash, 0) if($cmd eq "off");
	STREAMDECK_Redraw($hash) if $cmd eq "redraw";
	STREAMDECK_Level($hash, $a[2]) if $cmd eq "page";
	
}

sub STREAMDECK_Brightness_Toggle($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	STREAMDECK_Brightness($hash, $hash->{brightnesslevel} ? 0 : $attr{$name}{brightness});
}

sub STREAMDECK_Brightness($$) {
	my ($hash, $value) = @_;
	my $name = $hash->{NAME};

	return "brightness must be between 0 and 100" unless $value >= 0 and $value <= 100;
	
	$hash->{brightnesslevel} = $value;
	my $datax = pack("H*", "0555aad101" . sprintf("%02X", $value). "00"x11);
	my $setfeaturemagic = 1074546694;
	my $ret = ioctl($hash->{DIODev}, $setfeaturemagic, $datax) if $hash->{DIODev};

	Log3 $name, 5, "Set brightness to $value% rc:$ret";
	return undef;
}

sub STREAMDECK_SetState($$$$) {
  my ($hash, $tim, $vt, $val) = @_;
	my $name = $hash->{NAME};
  Log3 $name, 3,"STREAMDECK_SetState: $tim $vt $val";
  
  STREAMDECK_OnOpened($hash) if $vt eq "state" and $val eq "opened";
  return undef;
}

sub STREAMDECK_OnOpened($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3, "STREAMDECK: $name opened";
	
	$hash->{opened} = 1;

	STREAMDECK_Redraw($hash);
}

sub STREAMDECK_Redraw($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my %wasset;
	
	#restore images after device reconnect
	GP_ForallClients($hash, sub {
		my $client = shift;
		$wasset{$client->{key}} = 1 if STREAMDECK_KEY_SetImage($client);
	});
	
	# make all others black
	for (1..15) {
		STREAMDECK_SendImage($name, $hash, $_, "\0" x 15552) unless $wasset{$_};
	}
	
	
}


sub STREAMDECK_Level($$) {
	my ($hash, $page) = @_;
	my $name = $hash->{NAME};

	$hash->{page} = $page;
	STREAMDECK_Redraw($hash);
}

sub STREAMDECK_DoInit($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3, "STREAMDECK: $name Initialization";
}

sub STREAMDECK_CreateImage($$) {
	my ($hash, $v) = @_;
	my $name = $hash->{NAME};
	
	my $cachefile = STREAMDECK_GenCacheFilename($hash, $v, 'bin');
	if (-e $cachefile) {
		Log3 $name, 5, "image $name cache hit";
		open (FILE, "< $cachefile");
		binmode FILE;
		read FILE, my $bitmapdata, 15552;
		return $bitmapdata;
	}
	
	Log3 $name, 5, "image $name cache miss";

	my $image = Image::Magick->new();

	if ($v->{iconPath}) {
		my $issvg = $v->{iconPath} =~ ".svg";
		my $svgfill = $v->{svgfill} || 'white'; #svgfill is default white because default bg is black

		if($issvg) {
			$image->Set(size=>"720x720", background=>'transparent'); #import it larger, then resize
			
			# read file and replace fill into tempfile
			my $svgfillfile = STREAMDECK_GenCacheFilename($hash, $v, 'svg');
			open ORIGINALIMAGE, '<', $v->{iconPath};		
			open TMP, '>', $svgfillfile;
			
			while(<ORIGINALIMAGE>) {
				$_ =~ s/fill="#000000"/fill="$svgfill"/g;
				$_ =~ s/fill:#000000/fill:$svgfill/g;
				print TMP $_;
			}
			close ORIGINALIMAGE;
			close TMP;

			$image->Read($svgfillfile);
		} else {
			$image->Read($v->{iconPath});
		}

		# resize the image
		$image->Resize(geometry => "72x72") if !$v->{resize};
		$image->Resize(geometry => $v->{resize}) if $v->{resize} =~ 'x';

		# position the image
		my $icongravity = $v->{icongravity} || 'center';

		if (defined $v->{iconx} && defined $v->{icony}) {
			$image->Extent(geometry => "72x72", gravity=>$icongravity, x=>$v->{iconx}, y=>$v->{icony}, background=>$v->{bg});
		} else {
			$image->Extent(geometry => "72x72", gravity=>$icongravity, background=>$v->{bg});
		}
	} else {
		$image->Set(size=>"72x72");
		$image->Read('canvas:'.$v->{bg});
	}
	
	if($v->{text}) {
		my $textsize = $v->{textsize} || 16;
		my $textfill = $v->{textfill} || 'white';
		my $textstroke = $v->{textstroke} || 'transparent';
		my $textgravity = $v->{textgravity} || 'south';
		my $textfont = $v->{font};
		
		my $ret = $image->Annotate(
			text=>$v->{text},
			antialias=>1,
			gravity=>$textgravity, 
			font=>$textfont, 
			pointsize=>$textsize, 
			fill=>$textfill, 
			stroke=>$textstroke, 
			x=>0, y=>0);
		Log3 $name, 3, "image annotate rc=$ret" if $ret;
	}	
	
	$image->Crop(geometry => "72x72", x=>0, y=>0);
	$image->Rotate($v->{rotate}) if $v->{rotate};
	$image->Flop(); #image is expected mirrored on streamdeck
	my @pixels = $image->GetPixels(width => 72, height => 72, map => 'BGR');
	my $bitmapdata = join('', map { pack("H", sprintf("%04x", $_)) } @pixels);
	undef $image; #cleanup

	# write to cachefile
	open (FILE, "> $cachefile");
	binmode FILE;
	print FILE $bitmapdata;
	close(FILE);
	
	return $bitmapdata;
}

sub STREAMDECK_GenCacheFilename($$$) {
	my ($hash, $v, $ext) = @_;
	my $name = $hash->{NAME};
	my $value = join("|", map{ $_.":".$v->{$_} } sort keys %{$v});
	my $id = $name."_".sha1_hex($value);
	Log3 $name, 5, "Generated hash $id for $value";

	return "/tmp/streamdeck.cache.$id.$ext";
}

sub STREAMDECK_SendImage($$$$) {
	my ($name, $iodev, $key, $data) = @_;

	if(length($data) != 15552) {
		Log3 $name, 3, "invalid image data created for $name, length=".length($data);
		return;
	}
	Log3 $name, 5, "Setting $name image...";

	# Store the last image created, and simply restore it in case the device was unplugged.
	#$hash->{helper}{LASTIMGDATA} = $data;
	
	my $hkey = sprintf("%02X", $key);
	my $filler = pack("H*","00"x4096);

	my $header1 = pack("H*", "0201010000". $hkey ."00000000000000000000424df63c000000000000360000002800000048000000480000000100180000000000c03c0000c40e0000c40e00000000000000000000");
	my $header2 = pack("H*", "0201020001". $hkey ."00000000000000000000");

	my $header1_len = length($header1);
	my $header2_len = length($header2);
	my $data1_maxlen = 7749; # first page has 7749 bytes
	my $data2_maxlen = 7803; # first page has 7803 bytes
	
	
	my $datax = $header1 . substr($data, 0, $data1_maxlen) . substr($filler, 0, 8191 - $header1_len - $data1_maxlen).
				$header2 . substr($data, $data1_maxlen)    . substr($filler, 0, 8191 - $header2_len - $data2_maxlen);

	
	# this hack is needed for the images not being garbled if the first byte of syswrite is 0.
	substr($datax, 4096, 1) = chr(0x1) if ord(substr($datax, 4096, 1)) == 0;
	substr($datax, 8191+4096, 1) = chr(0x1) if ord(substr($datax, 8191+4096, 1)) == 0;
		
	# check readyness
	my $openresult = open (my $file, ">", $iodev->{file});

	# Need to send in chunks of not more than 4k
	if($openresult) {
		flock($file, LOCK_EX) or die "Could not lock '$file' - $!";
		Log3 $name, 5, "Writing $name image to streamdeck key $key...";

		syswrite($file, $datax, 4096, 0);  
		syswrite($file, $datax, 4095, 4096);
		syswrite($file, $datax, 4096, 8191);
		syswrite($file, $datax, 4095, 8191+4096);
		close $file;
		Log3 $name, 5, "Setting image... done";
	} else {
		Log3 $name, 3, "IODEV not open! not setting image for $name";
	}
}

# called from the global loop, when the select for hash->{FD} reports data
sub STREAMDECK_Read($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "STREAMDECK_READ";

	
	#Read on Device
	my $buffer = DevIo_SimpleRead($hash);
	my $len = length($buffer);
	if(!defined($buffer)) {
		Log3 $name, 3,"STREAMDECK_Read failed. empty buffer";
		DevIo_Disconnected($hash);
		return "";
	}
	
	my $hexline = unpack('H*', $buffer);
	if(length($buffer) != 17) {
		Log3 $name, 3,"STREAMDECK_Read unexpected length read: '$hexline' $len";
		return undef;
	}

	my ($type, @values) = unpack('C*', $buffer);
	
	if($type != 1) {
		Log3 $name, 5,"STREAMDECK_Read unexpected prefix byte. was not 01";
		return undef;
	}
	
	#process 
	GP_ForallClients($hash, sub {
		my $client = shift;
		my $clientKey = $client->{key};
		my $value = $values[$clientKey -1];
		
		if(AttrVal($client->{NAME}, 'page', 'root') eq $hash->{page}) {
			STREAMDECK_KEY_PRESSED($client, $value);
		}
	});

	Log3 $name, 5,"STREAMDECK_Read - END";
	return undef;
}

# Function to check if the device is back again
sub STREAMDECK_Ready($) {
	my ($hash) = @_;
	my $dev = $hash->{DeviceName};
	my $name = $hash->{NAME};
	my $ret = undef;
	
	if($hash->{STATE} eq "disconnected") {
		$ret = DevIo_OpenDev($hash, 1, "STREAMDECK_DoInit")
	}
	
	return $ret;
}

sub STREAMDECK_Attr($$$$) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $defs{$name};
  
	STREAMDECK_Brightness($hash, $value) if $attribute eq "brightness";  

  #lOG3 undef, 1, "COMMANDS:: ".Dumper(\%cmds);

}



1;

=pod
=begin html

<a name="STREAMDECK"></a>
<h3>STREAMDECK</h3>
<ul>
    STREAMDECK is a fhem-Modul to control the Elgato Stream Deck <br><br>
    
    Access to the USBRAW device (usually /dev/hidraw?) is needed<br>
</ul>
=end html
=begin html_DE

<a name="STREAMDECK"></a>
<h3>STREAMDECK</h3>
<ul>
    STREAMDECK ist ein a fhem-Modul f�r das Elgato Stream Deck <br><br>
    
    Access to the USBRAW device (usually /dev/hidraw?) is needed<br>
</ul>
=end html_DE
=cut
