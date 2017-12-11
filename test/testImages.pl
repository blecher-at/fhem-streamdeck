use Image::Magick;

sub STREAMDECK_CreateImage($$) {
	my ($v, $file) = @_;
	my $image = Image::Magick->new();

	if ($v->{iconPath}) {
		$image->Read($v->{iconPath});
		
		$image->Resize(geometry => "72x72") if !$v->{resize};
		$image->Resize(geometry => $v->{resize}) if $v->{resize} =~ 'x';
		$image->Rotate($v->{rotate}) if $v->{rotate};
		$image->Extent(geometry => "72x72", gravity=>'Center', background=>$v->{bg});
		
		if($v->{text}) {
			$textsize = $v->{textsize} || 16;
			$textfill = $v->{textfill} || 'white';
			$textstroke = $v->{textstroke} || 'black';
			$textgravity = $v->{textgravity}|| 'south';
			$textfont = $v->{font};
			
			$image->Annotate(gravity=>$textgravity, 
				font=>$textfont, pointsize=>$textsize, 
				fill=>$textfill, x=>0, y=>0, stroke=>$textstroke, text=>$v->{text} );
			$image->Crop(geometry => "72x72", x=>0, y=>0);
		}
	}
	
	$image->Write($file);
}

sub test($$) {
	my ($v, $image) = @_;
	my %parsedvalue = split /:| /, $v;
	my $data = STREAMDECK_CreateImage(\%parsedvalue, $image);
}


test("iconPath:/opt/fhem/www/images/default/on.png bg:black text:foobar", "test001.png");
test("iconPath:/opt/fhem/www/images/default/on.png bg:black text:foobarextralong", "test002.png");