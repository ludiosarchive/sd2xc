#!/usr/bin/perl
#
# Copyright Eric Windisch, 2003.
# Licensed under the MIT license.
# Modified by Nicholas Petreley, March 2003
# Modified further by James Barron, June 2004
#
use strict;
use Image::Magick;
use Getopt::Long;
use Config::IniFiles;

sub shadow
{
	my($imageref, $swidth, $sheight, $shadowblur, $shadowblursigma, $shadowx, $shadowy, $shadowopacity) = @_;
	my ($pre_shadow,$shadow_img,$resized);

	$resized=Image::Magick->new(size=>$swidth."x".$sheight);
	$resized->ReadImage('xc:transparent');
	$resized->Set(type=>"TrueColorMatte");
	$resized->Composite(image=>$$imageref,compose=>"Over");

	#this is a template for making a shadow pixel by pixel
	#basically, a black and white image to represent alpha channel.
	$pre_shadow=$resized->Clone();
	$pre_shadow->Separate(channel=>'Alpha');
	$pre_shadow->GaussianBlur(radius=>$shadowblur,sigma=>$shadowblursigma);
	$pre_shadow->Roll(x=>$shadowx,y=>$shadowy);
	$pre_shadow->Negate();
	$pre_shadow->Modulate(brightness=>$shadowopacity);

	#prepare actual shadow image
	$shadow_img=Image::Magick->new(size=>$swidth."x".$sheight);
	$shadow_img->ReadImage('xc:black');
	$shadow_img->Set(type=>"TrueColorMatte");
	$shadow_img->Composite(compose=>'CopyOpacity',image=>$pre_shadow);

	#compose image and shadow and write to file
	$resized->Composite(image=>$shadow_img,compose=>'Difference');

	return $resized;
}

my ($config_file, $path, $name, $tmppath, $generator, $verbose, $inherits, $tmpscheme, $shadow, $shadowopacity, $shadowx, $shadowy, $shadowblur, $shadowblursigma, $testinput, $testoutput);

# default for variables
$verbose=1;
$shadow=0;
$shadowopacity=40;
$shadowx=6;
$shadowy=6;
$shadowblur=5;
$shadowblursigma=3;
$path="theme/";
$tmppath="tmp/";
$generator="/usr/X11R6/bin/xcursorgen";
$testinput="";
$testoutput="test.png";
# it seems that recursive inheritance does not yet exist.
$inherits="";


sub process {
	print "Usage:\n$0 [-v] [--name] [--inherits theme] [--shadow] [--shadow-x pixels] [--shadow-y pixels] [--shadow-blur size] [--shadow-blur-sigma size] [--shadow-opacity] [--generator xcursorgen-path] [--tmp temp-dir] [--input image] [--output image]";
	exit 0;
};

GetOptions (
'name=s'=>\$name,
'inherits=s'=>\$inherits,
'tmp=s'=>\$tmppath,
'shadow'=>\$shadow,
'v'=>\$verbose,
'generator=s'=>\$generator,
'<>' => \&process,
'help'=>\&process,
'shadow-x=i'=>\$shadowx,
'shadow-y=i'=>\$shadowy,
'shadow-blur=i'=>\$shadowblur,
'shadow-blur-sigma=i'=>\$shadowblursigma,
'shadow-opacity=i'=>\$shadowopacity,
'input=s'=>\$testinput,
'output=s'=>\$testoutput
);

if($name ne "")
{
	$path=$name . "/";
}

if($testinput ne "")
{
	my($image,$yoffset,$xoffset,$swidth,$sheight);
	$image=Image::Magick->new;
	$image->Read($testinput);
	$swidth = $image->Get('width') + $shadowx + $shadowblur;
	$sheight = $image->Get('height') + $shadowy + $shadowblur;
	$image=shadow(\$image, $swidth, $sheight, $shadowblur, $shadowblursigma, $shadowx, $shadowy, $shadowopacity);
	$image->Write(filename=>$testoutput);

	exit();
}
	

# make sure path and tmppath end in /
if ($path =~ /[^\/]$/) {
	$path=$path."/";
}
if ($tmppath =~ /[^\/]$/) {
	$tmppath=$tmppath."/";
}

if (! -d $path) {
	mkdir ($path);
}
if (! -d $path."cursors/") {
	mkdir ($path."cursors/");
}
if (! -d $tmppath) {
	mkdir ($tmppath);
}
$tmpscheme=$tmppath."Scheme.ini";

# I did this much nicer, but Perl < 5.8 choked.
open (INI, "< Scheme.ini") or die ("Cannot open Scheme.ini");
open (INF, ">", $tmpscheme);
while (<INI>) {
	unless (!/=/ && !/^\s*\[/) {
		#$config_file.=$_;
		print INF $_;
	}
}
close (INI);
close (INF);

my $cfg=new Config::IniFiles(-file=>$tmpscheme) or die ("Scheme.ini in wrong format? -".$@);
my @sections=$cfg->Sections;

my $filemap={
	Arrow=>["left_ptr","X_cursor","right_ptr","top_left_arrow","move",'4498f0e0c1937ffe01fd06f973665830'],
	Cross=>["tcross","cross","crosshair","cross_reverse","draped_box"],
	Hand=>["hand","hand1", "hand2",'9d800788f1b08800ae810202380a0822','e29285e634086352946a0e7090d73106'],
	IBeam=>"xterm",
	UpArrow=>"center_ptr",
	SizeNWSE=>["bottom_right_corner","top_left_corner","bd_double_arrow","lr_angle",'c7088f0f3e6c8088236ef8e1e3e70000'],
	SizeNESW=>["bottom_left_corner","top_right_corner","fd_double_arrow","ll_angle",'fcf1c3c7cd4491d801f1e1c78f100000'],
	SizeWE=>["sb_h_double_arrow", "left_side", "right_side","h_double_arrow",'028006030e0e7ebffc7f7070c0600140','14fef782d02440884392942c11205230'],
	SizeNS=>["double_arrow","bottom_side","top_side","v_double_arrow","sb_v_double_arrow",'00008160000006810000408080010102','2870a09082c103050810ffdffffe0204'],
	Help=>["question_arrow",'d9ce0ab605698f320427677b458ad60b'],
	Handwriting=>"pencil",
	AppStarting=>["left_ptr_watch", '08e8e1c95fe2fc01f976f1e063a24ccd', '3ecb610c1bf2410f44200f48c40d3599'],
	SizeAll=>"fleur",
	Wait=>"watch",
	NO=>["crossed_circle",'03b6e0fcb3499374a867c041f52298f0']
};

foreach my $section (@sections) {
	my ($filename);

	$filename=$section.".png";
	unless (-f $filename) {
		next;
	}

	my ($image, $x, $frames, $width, $height, $curout);

	$image=Image::Magick->new;
	$x=$image->Read($filename);
	warn "$x" if "$x";

	$frames=$cfg->val($section, 'Frames');
	$width=$image->Get('width')/$frames;
	$height=$image->Get('height');

	if (defined($filemap->{$section})) {
		$curout=$filemap->{$section};
	} else {
		$curout=$section;
	}

	my $array=-1;
	eval {
		if (defined (@{$curout}[0])) { };
	};
	unless ($@) {
		$array=0;
	}

	LOOP:
	my $outfile;

	if ($array > -1) {
		if (defined (@{$curout}[0])) {
			$outfile=pop @{$curout};
		} else {
			next;
		}
	} else {
		$outfile=$curout;
	}
	$outfile=$path."cursors/".$outfile;

	if ($verbose) {
		print "Writing to $section -> $outfile\n";
	}

	open (FH, "| $generator > \"$outfile\"");

	my $yoffset = $shadowy + $shadowblur;
	my $xoffset = $shadowx + $shadowblur;
	my $swidth = $width + $xoffset;
	my $sheight = $height + $yoffset;
	for (my $i=0; $i<$frames; $i++) {
		my ($tmpimg, $outfile);
		$outfile=$tmppath.$section.'-'.$i.'.png';
		$tmpimg=$image->Clone();

		$x=$tmpimg->Crop(width=>$width, height=>$height, x=>$i*$width, y=>0);
		warn "$x" if "$x";

		if ($shadow)
		{
			$tmpimg=shadow(\$tmpimg, $swidth, $sheight, $shadowblur, $shadowblursigma, $shadowx, $shadowy, $shadowopacity);
		}

		$x=$tmpimg->Write($outfile);
		warn "$x" if "$x";

		print FH "1 ".
		$cfg->val($section,'Hot spot x')." ".
		$cfg->val($section,'Hot spot y')." ".
		$outfile." ".
		$cfg->val($section,'Interval')."\n";
	}

	if ($array > -1) {
		goto LOOP;
	}
}

print "Writing theme index.\n";
open (FH, "> ${path}index.theme");
print FH <<EOF;
[Icon Theme]
Inherits=$inherits
EOF
close (FH);

print "Done. Theme wrote to ${path}\n";
