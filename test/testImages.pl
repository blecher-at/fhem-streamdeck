use Image::Magick;
use warnings;
#use strict;


sub STREAMDECK_CreateImage($$) {
	my ($v, $filename) = @_;
	#my $name = $hash->{NAME};
	
	my $image = Image::Magick->new();
	
	if ($v->{iconPath}) {
		my $issvg = $v->{iconPath} =~ ".svg";
		my $svgfill = $v->{svgfill} || 'white'; #svgfill is default white because default bg is black

		if($issvg) {
			$image->Set(size=>"720x720", background=>'transparent'); #import it larger, then resize

			open ORIGINALIMAGE, '<', $v->{iconPath};		
			my $data = do { local $/; <ORIGINALIMAGE> } ;
			close ORIGINALIMAGE;
			
			$data =~ s/fill="#000000"/fill="$svgfill"/g;
			$data =~ s/fill:#000000/fill:$svgfill/g;
			
			open TMP, '>', '/tmp.svg';
			print TMP $data;
			close TMP;
			
			$image->Read('/tmp.svg');
			
			print "image: $image";
			close IMAGE;
		} else {
			$image->Read($v->{iconPath});
		}

		# resize the image
		$image->Resize(geometry => "72x72") if !$v->{resize};
		#$image->Resize(geometry => $v->{resize}) if $v->{resize} =~ 'x';

		# position the image
		my $icongravity = $v->{icongravity} || 'center';
		my $xparam = defined $v->{iconx} ? 'x':undef;
		my $yparam = defined $v->{icony} ? 'y':undef;
		$image->Extent(geometry => "72x72", gravity=>$icongravity, $xparam=>$v->{iconx}, $yparam=>$v->{icony}, background=>$v->{bg});
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
	}	
	
	$image->Crop(geometry => "72x72", x=>0, y=>0);
	$image->Rotate($v->{rotate}) if $v->{rotate};
	$image->Flop(); #image is expected mirrored on streamdeck
	my @pixels = $image->GetPixels(width => 72, height => 72, map => 'BGR');

	my $bitmapdata = join('', map { pack("H", sprintf("%04x", $_)) } @pixels);
	$image->Write("out.png");
  
	undef $image; #cleanup
	
	print "done $bitmapdata ||\n";
	return $bitmapdata;
}

sub test($$) {
	my ($v, $image) = @_;
	my %parsedvalue = split /:| /, $v;
	my $data = STREAMDECK_CreateImage(\%parsedvalue, $image);
}

#test("iconPath:/opt/fhem/www/images/default/on.png bg:black text:foobar", "test001.png");
test("iconPath:/opt/fhem/www/images/fhemSVG/system_fhem_reboot.svg bg:grey svgfill:blue text:foobarextralong", "test003.png");