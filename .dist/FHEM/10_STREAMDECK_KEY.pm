#################################################################################
# 
# $Id: 10_STREAM_DECK_KEY $ 
#
# FHEM Module for Elgato Stream Deck
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
package main;

use strict;
use warnings;
use Image::Magick;
#use FileHandle;
#use Data::Dumper;

sub STREAMDECK_KEY_Initialize($) {
	my ($hash) = @_;

	require "$attr{global}{modpath}/FHEM/DevIo.pm";

	$hash->{DefFn}	= "STREAMDECK_KEY_Define";
	$hash->{AttrFn}	= "STREAMDECK_KEY_Attr";
	$hash->{NotifyFn} = "STREAMDECK_KEY_Notify";
	$hash->{AttrList}	= "disable:0,1 image ". $readingFnAttributes;
	$hash->{NotifyOrderPrefix} = "99-" # make sure notifies are called last
	#unshift $FW_iconDirs, "default";
	#@FW_iconDirs = split(":", "default:openautomation"));
}

sub STREAMDECK_KEY_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	if (@a < 4) {
		my $msg = "wrong syntax: define <name> STEAMDECK <parentdevicename> <keynum>";
		Log3 undef, 2, $msg;
		return $msg;
	}

  	my $name = $a[0];
  	my $parentdevice = $a[2];
	my $key = $a[3];

	$hash->{NAME} = $name;
	$hash->{key} = $key;
	$hash->{IODev} = $defs{$parentdevice};
	
	
	
	#Close Device to initialize properly
	DevIo_CloseDev($hash);

	my $ret = DevIo_OpenDev($hash, 1, "STREAMDECK_DoInit");
	return $ret;
}

sub STREAMDECK_KEY_Attr($$$$) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $defs{$name};
	my $iconPath = "";
	Log3 $name, 5, "Setting ATTR $name $command $attribute $value";

	ATTRIBUTE_HANDLER: {
	
		$attribute eq "image" and do {
			STREAMDECK_KEY_SetImage($hash, $attribute, $value);

		};
	};
}


sub STREAMDECK_KEY_Notify {
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};
	
	return "" if !$hash->{notifydevice};
	return "" if $dev->{NAME} ne $hash->{notifydevice};
	
	#Redraw on device state change
	STREAMDECK_KEY_SetImage($hash, "image", $attr{$name}{"image"});
}


sub STREAMDECK_KEY_SetImage($$$) {
	my ($hash,$attribute,$value) = @_;
	my $name = $hash->{NAME};
	my ($type, $vv, $extra) = split(":", $value);
			
	my %parsedvalue = split /:| /,$value;
	#Log3 $name, 5, "> Setting image to $value : ". Dumper(\%parsedvalue);

	if ($parsedvalue{icon}) {
		my $icon = $parsedvalue{icon};
		my $iconPath = $attr{global}{modpath}."/www/images/default/$icon";
		Log3 $name, 5, "Setting $name image to: $vv -> $iconPath $icon";

		$parsedvalue{iconPath} = $iconPath;
	}
	
	if ($parsedvalue{device}) {
		my $devicename = $parsedvalue{device};
		$hash->{notifydevice} = $devicename;
		my ($icon) = FW_dev2image($devicename);
		my $iconPath = $attr{global}{modpath}."/www/images/default/$icon.png";
		$parsedvalue{iconPath} = $iconPath;

		Log3 $name, 5, "Setting image to device $devicename state $icon";
	}
	
	if ($parsedvalue{color}) {
		$parsedvalue{bg} = $parsedvalue{color};
	}
	
	if (!$parsedvalue{bg}) {
		$parsedvalue{bg} = 'black';
		if ($parsedvalue{color}) {
           $parsedvalue{bg} = $parsedvalue{color};
		}
	}
	
	
	#Log3 $name, 5, "< Setting image to $value : ". Dumper(\%parsedvalue);
	my $data = STREAMDECK_KEY_CreateImage(\%parsedvalue);
	STREAMDECK_KEY_SendImage($hash, $data);
	
	return undef;
}


sub STREAMDECK_KEY_CreateImage($) {
	my $v = shift;
	my $image = Image::Magick->new();
	
	if ($v->{iconPath}) {
		$image->Read($v->{iconPath});
		
		$image->Resize(geometry => "72x72") if !$v->{resize};
		$image->Resize(geometry => $v->{resize}) if $v->{resize} =~ 'x';

		$image->Extent(geometry => "72x72", gravity=>'Center', background=>$v->{bg});
	} else {
		$image->Set(size=>"72x72");
		$image->ReadImage('canvas:' . $v->{bg});
	}
	
	my @pixels = $image->GetPixels(width => 72, height => 72, map => 'BGR');

	my $bitmapdata = join('', map { pack("H", sprintf("%04x", $_)) } @pixels);
	return $bitmapdata;
}

sub STREAMDECK_KEY_SendImage($$) {
	my ($hash, $data) = @_;
	my $iodev = $hash->{IODev};
	my $name = $hash->{NAME};

	if(length($data) != 15552) {
		Log3 $name, 5, "Illegal image data, length=".length($data);
		return;
	}
	
	# Store the last image created, and simply restore it in case the device was unplugged.
	$hash->{helper}{LASTIMGDATA} = $data;
	
	my $hkey = sprintf("%02X", $hash->{key});
	my $filler = pack("H*","00"x4096);

	my $header1 = pack("H*", "0201010000". $hkey ."00000000000000000000424df63c000000000000360000002800000048000000480000000100180000000000c03c0000c40e0000c40e00000000000000000000");
	my $header2 = pack("H*", "0201020001". $hkey ."00000000000000000000");

	my $header1_len = length($header1);
	my $header2_len = length($header2);
	my $data1_maxlen = 7749; # first page has 7749 bytes
	my $data2_maxlen = 7803; # first page has 7803 bytes
	
	
	my $datax = $header1 . substr($data, 0, $data1_maxlen) . substr($filler, 0, 8191 - $header1_len - $data1_maxlen).
				$header2 . substr($data, $data1_maxlen)    . substr($filler, 0, 8191 - $header2_len - $data2_maxlen);

	Log3 $name, 5, "Setting $name image to: ". length($datax);
	
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
}




1;

=pod
=begin html

<a name="STREAMDECK_KEY"></a>
<h3>STREAMDECK_KEY</h3>
<ul>
    STREAMDECK_KEY repräsentiert einen einzelnen Taster auf dem Elgato Stream Deck.
	Die Nummer der Tasten ist 1-15 und beginnt rechts oben:
</ul>
=end html
=begin html_DE

<a name="STREAMDECK"></a>
<h3>STREAMDECK</h3>
<ul>
    STREAMDECK_KEY repräsentiert einen einzelnen Taster auf dem Elgato Stream Deck.
	Die Nummer der Tasten ist 1-15 und beginnt rechts oben:
</ul>
=end html_DE
=cut
