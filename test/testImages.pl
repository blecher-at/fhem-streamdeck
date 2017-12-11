use Image::Magick;
use warnings;
use strict;

sub STREAMDECK_CreateImage($$) {
	my ($v, $file) = @_;
	my $image = Image::Magick->new;
	
	if ($v->{iconPath}) {
		
		$image->Read($v->{iconPath});
		if($v->{iconPath} =~ '.svg') {
			#$image->Set(size=>"288x288");
			#$image->ReadImage('canvas:white');
#			$image->Draw(fill=>'black', primitive=>'@'.$v->{iconPath}, size=>"288x288");
			#$image->Draw(fill=>'black', primitive=>{'@/opt/fhem/www/images/default/system_fhem_reboot.svg'}, size=>"288x288");
			$image->ReadImage($v->{iconPath});
			print "AOAALA";
		} else {
			#$image->Read($v->{iconPath});
		}
		
		$image->Resize(geometry => "72x72");
		#$image->Resize(geometry => $v->{resize}) if $v->{resize} =~ 'x';
		#$image->Rotate($v->{rotate}) if $v->{rotate};
		$image->Extent(geometry => "72x72", gravity=>'Center', background=>$v->{bg});
		
	}			
	print "AOAALA";

	my @pixels = $image->GetPixels(width => 72, height => 72, map => 'BGR');

	my $bitmapdata = join('', map { pack("H", sprintf("%04x", $_)) } @pixels);
	print "BITMAP: ".$bitmapdata;
	
	$image->Write($file);
}

sub test($$) {
	my ($v, $image) = @_;
	my %parsedvalue = split /:| /, $v;
	my $data = STREAMDECK_CreateImage(\%parsedvalue, $image);
}


#test("iconPath:/opt/fhem/www/images/default/on.png bg:black text:foobar", "test001.png");
test("iconPath:/opt/fhem/www/images/fhemSVG/system_fhem_reboot.svg bg:black svgcolor:red text:foobarextralong", "test003.png");