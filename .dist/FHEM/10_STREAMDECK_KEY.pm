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

my @STREAMDECK_KEY_ImageAttributes = qw(rotate device icon color bg font text textsize textfill textstroke textgravity);

sub STREAMDECK_KEY_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}	= "STREAMDECK_KEY_Define";
	$hash->{AttrFn}	= "STREAMDECK_KEY_Attr";
	$hash->{NotifyFn} = "STREAMDECK_KEY_Notify";

	$hash->{AttrList}	= join(" ", @STREAMDECK_KEY_ImageAttributes)." image disable:0,1 ". $readingFnAttributes;
	$hash->{NotifyOrderPrefix} = "99-" # make sure notifies are called last
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

	# if attr is set after device was opened, update
	RemoveInternalTimer($hash, "STREAMDECK_KEY_SetImage");
	InternalTimer(0, "STREAMDECK_KEY_SetImage", $hash) if $hash->{IODev}{opened};
	
	return undef;
}

sub STREAMDECK_KEY_Notify {
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME};
	my $devname = $dev->{NAME};
	
	return "" if $hash->{NOTIFYDEV} eq $name; #ignore updates from ourselves
	return "" if !$hash->{NOTIFYDEV};
	return "" if $devname ne $hash->{NOTIFYDEV};
	
	#Redraw on device state change
	Log3 $name, 5, "STREAMDECK_KEY_Notify from $devname, updating image $name";
	STREAMDECK_KEY_SetImage($hash);
}

sub STREAMDECK_KEY_PRESSED($$) {
	my ($hash, $value) = @_;
	my $stringvalue = $value ? "pressed" : "released";
	my $name = $hash->{NAME};
	
	#Log3 $name, 5, "Setting state $name $value";
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "pressed", $value);
	readingsBulkUpdate($hash, "lastpressed", 1) if $value;
	readingsBulkUpdateIfChanged($hash, "state", $stringvalue);
	readingsEndUpdate($hash, 1);
	
	if ( $value == 1 ) {
		my $lngpressInterval = AttrVal($hash->{NAME}, "longpressinterval", "2");
		InternalTimer(gettimeofday() + $lngpressInterval, 'STREAMDECK_KEY_longpress', $hash, 0);
	} else {
		RemoveInternalTimer('STREAMDECK_KEY_longpress');
	}

}

sub STREAMDECK_KEY_longpress($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $pressed = ReadingsVal($name, "pressed", 0);
	
	if ($pressed) {
		Log3 $name, 5, "Setting longpress";
		readingsSingleUpdate($hash, 'state', 'longpress', 1);
	}
}

sub STREAMDECK_KEY_SetImage($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $key = $hash->{key};

    RemoveInternalTimer($hash, 'STREAMDECK_KEY_SetImage');

	# get image attr from device and parse
	my $value = $attr{$name}{image}; 
	my %parsedvalue = split /:|[ |]/,$value;
	
	# set other attributes to the hash as they were defined directly
	foreach(@STREAMDECK_KEY_ImageAttributes) {
		$parsedvalue{$_} = $attr{$name}{$_} unless defined $parsedvalue{$_};
	}
	
	# magic parse text 
	if ($parsedvalue{text}) {
		#my $st = ;
		(undef, my $magictext) = ReplaceSetMagic($hash, 1, $parsedvalue{text});
		Log3 $name, 5, "ReplaceSetMagic text value $parsedvalue{text} to '$magictext'";
		$parsedvalue{text} = $magictext;
	}
		
	my $iconsloaded = FW_iconName("on.png");
	if (!$iconsloaded) {
		Log3 $name, 3, "Icons not yet initialized. triggering fhemweb init";
		FW_answerCall(undef); # workaround: trigger fake fhemweb request to initialize icons
	}

	if ($parsedvalue{device}) {
		# register and enable notify
		$hash->{NOTIFYDEV} = $parsedvalue{device};

		# read status icon. retry if no icon exists for this device
		my ($icon) = FW_dev2image($parsedvalue{device});
		if(!$icon) {
			#FW_answerCall(""); # workaround: trigger fake fhemweb request to initialize icons
			#InternalTimer(gettimeofday() + 5, 'STREAMDECK_KEY_SetImage', $hash, 1);
			my $d = $defs{$parsedvalue{device}};
			my $state = $d->{STATE};
			
			# default icon when state does not match any icon is the defined icon
			$icon = $parsedvalue{icon};
			$icon = "toggle.png" if !$icon; # use toggle if no fallback icon is defined
			Log3 $name, 5, "Setting $name image failed. no icon found for ".$parsedvalue{device}.": $state, fallback to $icon";
		}			
		$parsedvalue{icon} = $icon;

	}
	
	if ($parsedvalue{icon}) {
		my $icon = $parsedvalue{icon};
		my $iconPath = $attr{global}{modpath}."/www/images/".FW_iconPath(FW_iconName($icon));
		$parsedvalue{iconPath} = $iconPath;
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
	
	#Log3 $name, 5, "Setting image to $value = $parsedvalue{iconPath} $parsedvalue{bg}";
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
