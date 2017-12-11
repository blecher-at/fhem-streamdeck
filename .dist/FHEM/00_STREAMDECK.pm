#################################################################################
# 
# $Id: 00_STREAM_DECK $ 
#
# FHEM Module for Elgato Stream Deck
#
# Copyright (C) 2017 Stephan Blecher - www.blecher.at
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

######################################################################################
sub STREAMDECK_Clear($);
sub STREAMDECK_Read($);
sub STREAMDECK_Ready($);
sub STREAMDECK_Parse($$);
sub STREAMDECK_CmdConfig($);
sub STREAMDECK_ReInit($);


sub STREAMDECK_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{ReadFn}  = "STREAMDECK_Read";
  $hash->{ReadyFn} = "STREAMDECK_Ready";
  $hash->{DefFn}   = "STREAMDECK_Define";
  $hash->{UndefFn} = "STREAMDECK_Undef";
  $hash->{AttrFn}  = "STREAMDECK_Attr";
  $hash->{StateFn} = "STREAMDECK_SetState";
  $hash->{ShutdownFn} = "STREAMDECK_Shutdown";
  $hash->{AttrList}  = "disable:0,1 brightness ". $readingFnAttributes;
}

#####################################
# define <name> STEAMDECK <devicefile>

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


#####################################
sub STREAMDECK_Undef($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	DevIo_CloseDev($hash);
	return undef;
}


#####################################
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
	# TODO
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 3,"STREAMDECK: Initialization";
	
	#restore images after device reconnect
	GP_ForallClients($hash, sub {
		my $client = shift;

		if(length($client->{helper}{LASTIMGDATA})) {
			STREAMDECK_KEY_SendImage($client, $client->{helper}{LASTIMGDATA});
		}
	});

  
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

		my $clientName = $client->{NAME};
		my $clientKey = $client->{key};
		
		my $value = $values[$clientKey-1];
		Log3 $name, 5,"STREAMDECK_SETATTR - $clientName $value";

		my $newvalue = $value ? "pressed" : "released";

		readingsBeginUpdate($client);
		readingsBulkUpdate($client, "lastpressed", 1) if $value;
        readingsBulkUpdateIfChanged($client, "state", $newvalue);
        readingsEndUpdate($client, 1);
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



#####################################
sub STREAMDECK_Set($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3,"STREAMDECK_Set";
  return "no get value specified" if(@a < 2);

}

#####################################
sub STREAMDECK_Get($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3,"STREAMDECK_Get";
  return "no get value specified" if(@a < 2);
  

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
