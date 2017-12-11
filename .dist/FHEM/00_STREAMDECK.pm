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
use threads;
use DevIo;

######################################################################################
sub STREAMDECK_Clear($);
sub STREAMDECK_Read($);
sub STREAMDECK_Ready($);
sub STREAMDECK_Parse($$);
sub STREAMDECK_CmdConfig($);
sub STREAMDECK_ReInit($);


sub STREAMDECK_Initialize($) {
  my ($hash) = @_;

  $hash->{ReadFn}  = "STREAMDECK_Read";
  $hash->{ReadyFn} = "STREAMDECK_Ready";
  $hash->{DefFn}   = "STREAMDECK_Define";
  $hash->{UndefFn} = "STREAMDECK_Undef";
  $hash->{AttrFn}  = "STREAMDECK_Attr";
  $hash->{StateFn} = "STREAMDECK_SetState";
  $hash->{ShutdownFn} = "STREAMDECK_Shutdown";
  $hash->{AttrList}  = "disable:0,1 brightness ". $readingFnAttributes;
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


sub STREAMDECK_SetState($$$$) {
  my ($hash, $tim, $vt, $val) = @_;
	my $name = $hash->{NAME};
  Log3 $name, 3,"STREAMDECK_SetState: $tim $vt $val";
  return undef;
}


sub STREAMDECK_Clear($) {
  return undef;
}

sub STREAMDECK_DoInit($$) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3, "STREAMDECK: $name Initialization";
	
	# set black as default
	my %parsedvalue = ();
	$parsedvalue{bg} = "black";
	my $data = STREAMDECK_CreateImage(\%parsedvalue);
	
	for (1..15) {
		STREAMDECK_SendImage($name, $hash, $_, $data);
	}
	
	#restore images after device reconnect
	GP_ForallClients($hash, sub {
		my $client = shift;

		if(length($client->{helper}{LASTIMGDATA})) {
			STREAMDECK_KEY_SendImage($client, $client->{helper}{LASTIMGDATA});
		}
	});

}


sub STREAMDECK_CreateImage($) {
	my ($v) = @_;
	my $image = Image::Magick->new();
	
	if ($v->{iconPath}) {
		$image->Read($v->{iconPath});
		
		$image->Resize(geometry => "72x72") if !$v->{resize};
		$image->Resize(geometry => $v->{resize}) if $v->{resize} =~ 'x';
		$image->Rotate($v->{rotate}) if $v->{rotate};
		my $icongravity = $v->{icongravity} || 'center';
		
		$image->Extent(geometry => "72x72", gravity=>$icongravity, background=>$v->{bg});
		#$image->Annotate(gravity=>'south', font=>'Arial', pointsize=>10, fill=>'white', x=>0, y=>0, text=>"NORAD" );
		#$image->Crop(geometry => "72x72", x=>0, y=>0);
		
		if($v->{text}) {
			my $textsize = $v->{textsize} || 16;
			my $textfill = $v->{textfill} || 'white';
			my $textstroke = $v->{textstroke} || 'black';
			my $textgravity = $v->{textgravity} || 'south';
			my $textfont = $v->{font};
			
			$image->Annotate(
				text=>$v->{text},
				antialias=>1,
				gravity=>$textgravity, 
				font=>$textfont, 
				pointsize=>$textsize, 
				fill=>$textfill, 
				x=>0, y=>0);
			$image->Crop(geometry => "72x72", x=>0, y=>0);
		}
		$image->Flop(); #image is expected mirrored on streamdeck
	}
	
	my @pixels = $image->GetPixels(width => 72, height => 72, map => 'BGR');

	my $bitmapdata = join('', map { pack("H", sprintf("%04x", $_)) } @pixels);
	return $bitmapdata;
}


sub STREAMDECK_SendImage($$$$) {
	my ($name, $iodev, $key, $data) = @_;

	if(length($data) != 15552) {
		Log3 $name, 3, "Illegal image data, length=".length($data);
		return;
	}
	
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

	Log3 $name, 9, "Setting $name image...";
	
	# this hack is needed for the images not being garbled if the first byte of syswrite is 0.
	substr($datax, 4096, 1) = chr(0x1) if ord(substr($datax, 4096, 1)) == 0;
	substr($datax, 8191+4096, 1) = chr(0x1) if ord(substr($datax, 8191+4096, 1)) == 0;
	
	
	# Need to send in chunks of not more than 4k
	if($iodev->{DIODev}) {
		syswrite($iodev->{DIODev}, $datax, 4096, 0);  
		syswrite($iodev->{DIODev}, $datax, 4095, 4096);
		syswrite($iodev->{DIODev}, $datax, 4096, 8191);
		syswrite($iodev->{DIODev}, $datax, 4095, 8191+4096);
	}
	Log3 $name, 9, "Setting image... done";
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
		STREAMDECK_KEY_PRESSED($client, $value);
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
	
	#Log3 $name, 5, "STREAMDECK_Ready $ret";
	return $ret;
}

sub STREAMDECK_Attr($$$$) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $defs{$name};
  
	ATTRIBUTE_HANDLER: {
		$attribute eq "brightness" and do {
			my $datax = pack("H*", "0555aad101" . sprintf("%02X", $value). "0000000000000000000000");
			syswrite($hash->{DIODev}, $datax);

			Log3 $name, 5, "Set brightness to $value";
			return undef;
		};
	};
  
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
    STREAMDECK ist ein a fhem-Modul für das Elgato Stream Deck <br><br>
    
    Access to the USBRAW device (usually /dev/hidraw?) is needed<br>
</ul>
=end html_DE
=cut
