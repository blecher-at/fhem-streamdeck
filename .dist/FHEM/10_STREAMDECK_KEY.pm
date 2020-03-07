#################################################################################
# 
# $Id: 10_STREAM_DECK_KEY $ 
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
package main;

use strict;
use warnings;
use Blocking;

use vars qw($FW_wname);   # Web instance

my @STREAMDECK_KEY_ImageAttributes = qw(rotate device devstatecolorattr icon color bg font longpressinterval svgfill text textsize textfill textstroke textgravity stylesheetPrefix);

sub STREAMDECK_KEY_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}	= "STREAMDECK_KEY_Define";
	$hash->{AttrFn}	= "STREAMDECK_KEY_Attr";
	$hash->{NotifyFn} = "STREAMDECK_KEY_Notify";

	$hash->{AttrList}	= join(" ", @STREAMDECK_KEY_ImageAttributes)." image page disable:0,1 ". $readingFnAttributes;
	$hash->{NotifyOrderPrefix} = "1-"; # make sure notifies are called first, image is updated async anyway

	LoadModule("FHEMWEB");
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
	$hash->{IODevName} = $parentdevice;
	$hash->{NOTIFYDEV} = $name; #set to ourselves, might be replaced by device
	
	return undef;
}

sub STREAMDECK_KEY_Attr($$$$) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $defs{$name};
	my $iconPath = "";
	Log3 $name, 5, "Setting ATTR $name $command $attribute $value";

	# get image attr from device and parse
	$attr{$name}{$attribute} = $value; 
	
	my %parsedvalue = ();
	
	if($attr{$name}{image}) {
		%parsedvalue = split /:|[ |]/,$attr{$name}{image};
	}
	
	# set other attributes to the hash as they were defined directly
	foreach(@STREAMDECK_KEY_ImageAttributes) {
		$parsedvalue{$_} = $attr{$name}{$_} if defined $attr{$name}{$_};
	}
	
	$hash->{NOTIFYDEV} = $parsedvalue{device} if ($parsedvalue{device});
	$hash->{parsedattr} = {%parsedvalue};

	# if attr is set after device was opened, update
	RemoveInternalTimer($hash, "STREAMDECK_KEY_SetImage");
	InternalTimer(0, "STREAMDECK_KEY_SetImage", $hash) if $hash->{IODev}{opened};
	
	return undef;
}

sub STREAMDECK_KEY_Notify {
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};
	my $devname = $dev->{NAME};
	my $notifydev = $hash->{NOTIFYDEV};
	
	return "" if $hash->{NOTIFYDEV} eq $name; #ignore updates from ourselves
	return "" if !$hash->{NOTIFYDEV};
	return "" if $devname ne $hash->{NOTIFYDEV};
	
	my $state = Value($devname);
	#Redraw on device state change
	Log3 $name, 5, "STREAMDECK_KEY_Notify from $devname, updating image for $name:$state";
	STREAMDECK_KEY_SetImage($hash);
	return;
}

sub STREAMDECK_KEY_PRESSED($$) {
	my ($hash, $value) = @_;
	my $stringvalue = $value ? 'pressed' : 'released';
	my $name = $hash->{NAME};
	
	#Log3 $name, 5, "Setting state $name $value";
	
	readingsBeginUpdate($hash);
	readingsBulkUpdateIfChanged($hash, 'state', $stringvalue);
	readingsBulkUpdateIfChanged($hash, 'value', $value);
	
	if ( $value == 1 ) {
		my $longpressInterval = AttrVal($hash->{NAME}, 'longpressinterval', 1);
		if($longpressInterval) {
			InternalTimer(gettimeofday() + $longpressInterval, 'STREAMDECK_KEY_longpress', $hash, 0);
		}
	} else {
		RemoveInternalTimer($hash, 'STREAMDECK_KEY_longpress');
		readingsBulkUpdateIfChanged($hash, 'longpresstime', 0, 1);
	}

	readingsEndUpdate($hash, 1);

}

sub STREAMDECK_KEY_longpress($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $pressed = ReadingsVal($name, 'value', 0);
	
	if ($pressed) {
		my $longpressInterval = AttrVal($hash->{NAME}, 'longpressinterval', 1);
		my $longpresstime = ReadingsVal($name, 'longpresstime', 0) + 1;
		Log3 $name, 5, "Setting longpress";
		readingsBeginUpdate($hash);
		readingsBulkUpdateIfChanged($hash, 'longpresstime', $longpresstime, 1);
		readingsBulkUpdateIfChanged($hash, 'state', 'longpress '.$longpresstime, 1);
		readingsEndUpdate($hash, 1);
		
		InternalTimer(gettimeofday() + $longpressInterval, 'STREAMDECK_KEY_longpress', $hash, 0);
	}
}

sub STREAMDECK_KEY_SetImage($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $key = $hash->{key};
	
	if(AttrVal($name, 'page', 'root') eq $hash->{IODev}{page}) {
		RemoveInternalTimer($hash, 'STREAMDECK_KEY_SetImage');
		Log3 $name, 5, "Starting STREAMDECK_KEY_SetImage_Blocking $name";
		BlockingCall("STREAMDECK_KEY_SetImage_Blocking", $name);
		return 1;
	}
	return 0;
}

# image generation takes up to a few seconds,
# we moved this to BlockingCall for better performance. 
sub STREAMDECK_KEY_SetImage_Blocking($) {
	my ($name) = @_;
	my $hash = $defs{$name};
	my $key = $hash->{key};
	
	# Hack to use icondirs defined here not in fhemweb. see https://forum.fhem.de/index.php/topic,81748.0.html. 
	# safe to override icondirs, we are in a fork anyway
	$attr{$FW_wname}{stylesheetPrefix} = $attr{$name}{stylesheetPrefix}; 
	FW_answerCall("robots.txt");

	my %parsedvalue = %{$hash->{parsedattr}};
	
	# magic parse text 
	foreach my $key (keys %parsedvalue) { 
		if($parsedvalue{$key}) {
			(undef, my $magic) = ReplaceSetMagic($hash, 1, $parsedvalue{$key});
			Log3 $name, 5, "ReplaceSetMagic $key: value ".$parsedvalue{$key}." to '$magic'";
			$parsedvalue{$key} = $magic;
		}
	}

	if ($parsedvalue{device}) {
		# read status icon. fallback to default if no icon exists for this device
		my ($icon) = FW_dev2image($parsedvalue{device});
		if(!$icon) {
			# default icon when state does not match any icon is the defined icon
			$icon = $parsedvalue{icon};
			$icon = "toggle.png" if !$icon; # use toggle if no fallback icon is defined
			my $state = Value($parsedvalue{device});
			Log3 $name, 5, "Setting $name image failed. no icon found for ".$parsedvalue{device}.": $state, fallback to $icon";
		}			
		$parsedvalue{icon} = $icon;
	}
	
	
	
	if ($parsedvalue{icon}) {
		my ($icon, $color) = split '@', $parsedvalue{icon};
		my $iconPath = $attr{global}{modpath}."/www/images/".FW_iconPath(FW_iconName($icon));
		$parsedvalue{iconPath} = $iconPath;

		# devstatecolorattr contains the attribute that is set by the color of the device state
		# default is 'svgfill'. the other reasonable attribute is 'bg'
		my $colorattr = $parsedvalue{devstatecolorattr} || 'svgfill';
		if ($color and !$parsedvalue{$colorattr}) {
			$parsedvalue{$colorattr} = $color;
		}
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
	
	$parsedvalue{rotate} = AttrVal($hash->{IODevName}, "rotate", 0) unless $parsedvalue{rotate};
	
	#Log3 $name, 5, "Setting image to $parsedvalue{iconPath} $parsedvalue{bg}";
	my $data = STREAMDECK_CreateImage($hash, \%parsedvalue);
	STREAMDECK_SendImage($name, $hash->{IODev}, $key, $data);
	
	return undef;
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
