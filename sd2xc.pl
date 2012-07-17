#!/usr/bin/perl
#
# Copyright Eric Windisch, 2003.
# Licensed under the MIT license.
# Modified by Nicholas Petreley, March 2003
# Modified further by James Barron, June 2004
# Modified further by Moony, October 2007, December 2007
#	Disclaimer: This code may look like crap and / or contain poor coding practices.
#	            Well, you got it for free, so be happy!
#
#	Version 2.1
#	Installation (to ~/.icons) option:  --install
#	Added option to not create tar.gz of theme:  --nozip
#	Added option to keep temporary files:  --keep-temp
#	Reworked the --help option to give a better display and more info
#	Fixed some issues with ini rewriting
#	Added native version identifier
#	Renamed default temp directory to something less scary to delete (was tmp)
#
#	Version 2.0
#	Started using version numbers, for my own sake. Sorry.  ;)
#	Fixed shadow algorithm (how come nobody fixed it sooner??!)
#	Automatically creates a .tar.gz file of X11 cursors.
#	Added opacity options
#	Added additional defaults to make all input options optional
#	Added support for Stardock "_Scripts" ini option which allows frames
#	  to be shown in any order
#
# Features: 
# * Converts CursorXP themes to X11 themes 
# * Animations are supported 
# * Can add customized drop shadows 
# * Can now install the theme for you
# * Can modify opacity 
# * Honors CursorXP "Script" options to show animation frames in any order 
# * Creates a .tar.gz file automatically 
# 
# 
# Using it: 
# * Extract the tar.gz file to some directory in your PATH (like /usr/bin) 
# * Extract a *.CurXPTheme (Rename to *.zip if necessary) 
# * Change to the directory of the extracted theme, where a Scheme.ini file is 
# * Run: sd2xc-##.pl --help (for help, duh) 
# * Run: sd2xc-##.pl --name theme_name --install
# * A tar.gz file will be created inside that directory containing the X11 theme
# * It will install to your ~/.icons folder if you use --install option.
# * Send to grandma. She will love it! 
# 
# Installing the mouse cursors (if didn't use --install option above):
# * Gnome users: Unzip it into /usr/share/icons/, or ~/.icons/ . Then use gnome-appearance-properties to change cursor 
# * KDE Users: Use "Control Center / Peripherals / Mouse / Cursor Theme" to install the tar.gz file, then re-login

#
# Requirements:
# Requires packages:   ImageMagick ImageMagick-perl perl-Config-IniFiles xcursorgen
# Installation varies by distro.  Fedora users can do:
#    yum install ImageMagick ImageMagick-perl perl-Config-IniFiles xcursorgen
# Ubuntu users may be able to do something like:
#    sudo apt-get install libconfig-inifiles-perl perlmagick imagemagick xcursorgen


use strict;
use Image::Magick;
use Getopt::Long;
use Config::IniFiles;

my ($config_file, $path, $name, $tmppath, $generator, $verbose, $inherits, $tmpscheme, $shadow, $shadowopacity, $shadowx, $shadowy, $shadowblur, $shadowblursigma, $testinput, $testoutput, $opacity, $install, $nozip, $keeptemp, $printversion, $version);

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
	$pre_shadow->Roll(x=>$shadowx,y=>$shadowy);
	$pre_shadow->GaussianBlur(radius=>$shadowblur,sigma=>$shadowblursigma);
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
sub opacity 
{
	my($imageref, $opacity) = @_;
	my $opacity_img;
	my $factor = $opacity / 100;

	$opacity_img=$$imageref->Clone(); 
	$opacity_img->Evaluate(value=>$factor, operator=>'Multiply', channel=>'Alpha');

	return $opacity_img;
}

sub resize
{
	my($imageref, $factor) = @_;
	my ($sheight, $swidth) = $$imageref->Get('height', 'width');
	my $resized;
	my $heightplus1 = $sheight + 1;
	my $widthplus1 = $swidth + 1;
	my $newwidth = int($swidth * ($factor / 100) + 2);
	my $newheight = int($sheight * ($factor / 100)+ 2);


	$resized=Image::Magick->new(size=>$widthplus1."x".$heightplus1);
	$resized->ReadImage('xc:transparent');
	$resized->Set(type=>"TrueColorMatte");
	$resized->Composite(image=>$$imageref,compose=>"Over");
	$resized->Roll(x=>'1',y=>'1');

	#prepare actual shadow image
	#$scaled_img=$$imageref->Clone(); 
	$resized->Resize(geometry=>$newwidth."x".$newheight,filter=>'Cubic',blur=>'1.0',support=>'1');

	return $resized;
}

# Rewrite Scheme.ini to tempfile (to number the lines) if contains "Script" information 
# necessary because Stardock doesn't follow INI specs in this case
# hence perl doesn't read it in properly

sub rewrite_ini {
	my $filename = shift();
	open(INI, $filename) or die "Could not open Scheme.ini file: $!";
	open(INIOUT, ">$tmpscheme.tmp"); #open for write, overwrite

	my $atheader = 0;
	my $inscriptheader = 0;
	my $scriptheadercounter = 0;
	my $cursortitle;
	my $cursorfile;
	my $line;

	foreach $line (<INI>) {
		chomp($line);              # remove the newline from $line.
		if ($line =~ m/^.*\[.*_Script\]\s*$/){
			if ($atheader eq "0" ){
				print INIOUT $line."\n";

				$inscriptheader = 1;
				$scriptheadercounter = 0;
				$atheader = 1;
			} else {
				die "Incorrect ini format";
			}
		} elsif ($line =~ m/^.*\[.*\]\s*$/){
			if ($atheader eq "0" ){
				print INIOUT $line."\n";

				$inscriptheader = 0;
				$scriptheadercounter = 0;
				$atheader = 1;
			} else {
				die "Incorrect ini format";
			}
		} elsif ($line !~ m/^\s*$/){
			if ($inscriptheader eq "1"){
				print INIOUT $scriptheadercounter."=".$line."\n";
				$scriptheadercounter = $scriptheadercounter + 1;
				$atheader = 0;
				
			} else {
				print INIOUT $line."\n";
				$atheader = 0;
				$inscriptheader = 0;

			}
		}
	

		
	}
	close (INIOUT);

}

                                                                                                                                                                             


# default for variables
$version="2.1";
$verbose=1;
$shadow=0;
$shadowopacity=40;
$opacity=100;
$shadowx=6;
$shadowy=6;
$shadowblur=5;
$shadowblursigma=3;
$path="theme/";
$tmppath="temp-sd2xc/";
$generator=`which xcursorgen`;
$generator =~ s/\n//g;
if ($generator !~ m/xcursorgen/){ die "No xcursorgen installed." }
$testinput="";
$testoutput="test.png";
$name="cursor-theme";
# it seems that recursive inheritance does not yet exist.
$inherits="core";
$install=0;
$nozip=0;
$keeptemp=0;


sub process {
	print "Usage:\n$0 \n";
	print "\t[-v]                         \tVerbose output\n";
	print "\t[--name theme_name]          \tName for X11 theme being output (default = cursor-theme)\n";
	print "\t[--inherits theme]           \tInherits existing theme (default = core)\n"; 
	print "\t[--shadow]                   \tApply a drop shadow to cursors\n"; 
	print "\t[--shadow-x pixels]          \tDrop shadow offset horizontal (default = 6)\n"; 
	print "\t[--shadow-y pixels]          \tDrop shadow offset vertical (default = 6)\n"; 
	print "\t[--shadow-blur size (pixels)]\tGaussian blur size (default = 5)\n"; 
	print "\t[--shadow-blur-sigma size]   \tGaussian blur sigma (default = 3)\n"; 
	print "\t[--shadow-opacity 0-100]     \tOpacity of drop shadow (default = 40)\n"; 
	print "\t[--overall-opacity 0-100]    \tOverall opacity of cursors (default = 100)\n"; 
	print "\t[--generator xcursorgen-path]\tLocation of xcursorgen (default = auto)\n"; 
	print "\t[--tmp temp-dir]             \tUse temporary directory (default = ./temp-sd2xc/)\n"; 
	print "\t[--input image]\t\n"; 
	print "\t[--output image]\t\n"; 
	print "\t[--install]                  \tInstall to ~/.icons/ \n"; 
	print "\t[--nozip]                    \tDon't Create tar.gz of theme \n"; 
	print "\t[--keep-temp]                \tDon't delete temporary files \n"; 
	print "\t[--version]                  \tPrint version information\n";
	print "\t[--help]                     \tThis help information\n";
	print "\nINFORMATION:  CursorXP themes (*.CurXPTheme) are simply zip files.  You can decompress them as such after renaming to *.zip.  Change to the directory of an extracted CursorXP theme prior to running!  There will be a Scheme.ini file there.  ";
	print "\nRecommended to at least provide:  --name theme_name\n";
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
'overall-opacity=i'=>\$opacity,
'input=s'=>\$testinput,
'output=s'=>\$testoutput,
'install'=>\$install,
'nozip'=>\$nozip,
'keep-temp'=>\$keeptemp,
'version'=>\$printversion
);

if ($printversion){
	print "$0 \n";
	print "\tVersion: $version\n";
	exit 0;
}

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
	$image=opacity(\$image, $opacity);
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

rewrite_ini("Scheme.ini");


# I did this much nicer, but Perl < 5.8 choked.
open (INI, "< $tmpscheme.tmp") or die ("Cannot open Scheme.tmp.ini");
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

my $filemap_script={
	Arrow_Script=>["left_ptr","X_cursor","right_ptr","top_left_arrow","move",'4498f0e0c1937ffe01fd06f973665830'],
	Cross_Script=>["tcross","cross","crosshair","cross_reverse","draped_box"],
	Hand_Script=>["hand","hand1", "hand2",'9d800788f1b08800ae810202380a0822','e29285e634086352946a0e7090d73106'],
	IBeam_Script=>"xterm",
	UpArrow_Script=>"center_ptr",
	SizeNWSE_Script=>["bottom_right_corner","top_left_corner","bd_double_arrow","lr_angle",'c7088f0f3e6c8088236ef8e1e3e70000'],
	SizeNESW_Script=>["bottom_left_corner","top_right_corner","fd_double_arrow","ll_angle",'fcf1c3c7cd4491d801f1e1c78f100000'],
	SizeWE_Script=>["sb_h_double_arrow", "left_side", "right_side","h_double_arrow",'028006030e0e7ebffc7f7070c0600140','14fef782d02440884392942c11205230'],
	SizeNS_Script=>["double_arrow","bottom_side","top_side","v_double_arrow","sb_v_double_arrow",'00008160000006810000408080010102','2870a09082c103050810ffdffffe0204'],
	Help_Script=>["question_arrow",'d9ce0ab605698f320427677b458ad60b'],
	Handwriting_Script=>"pencil",
	AppStarting_Script=>["left_ptr_watch", '08e8e1c95fe2fc01f976f1e063a24ccd', '3ecb610c1bf2410f44200f48c40d3599'],
	SizeAll_Script=>"fleur",
	Wait_Script=>"watch",
	NO_Script=>["crossed_circle",'03b6e0fcb3499374a867c041f52298f0']
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

		my $i=0;

		# Process and Output images
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
	
			if ($opacity)
			{
				$tmpimg=opacity(\$tmpimg, $opacity);
			}
		
			#$tmpimg=resize(\$tmpimg, "110");
	
			$x=$tmpimg->Write($outfile);
			warn "$x" if "$x";
		}
	
		# Manage the order that frames are displayed

		# If there is a _Script, process as such
		my $section_script=$section."_Script";
		if (defined ($cfg->val($section_script, "0"))){
			my $scripti = 0;
			my $i = 0;
			my $getinfo;
			my $interval;
			my $startframe;
			my $endframe;
			my $whichframes;

			while ($cfg->val($section_script, $scripti) ne ""){
				$startframe = "";
				$endframe = "";

				$getinfo=$cfg->val($section_script, $scripti);
				($whichframes, $interval) = split (/,/ , $getinfo);
				#print $frames." ".$interval."\n";

				($startframe, $endframe) = split (/-/ , $whichframes);

				if ($interval > 1000000){
					$interval = 1000000;
				}

				if ($endframe !~ /\d/ ){
					$endframe = $startframe;
				}

								
				for (my $i=$startframe-1; $i<$endframe; $i++) {
					my ($tmpimg, $outfile);
					$outfile=$tmppath.$section.'-'.$i.'.png';
# 		
					if (-e "$outfile"){
						print FH "1 ".
						$cfg->val($section,'Hot spot x')." ".
						$cfg->val($section,'Hot spot y')." ".
						$outfile." ".
						$interval."\n";
					}	
					
				}

				$scripti = $scripti + 1;
			}
			
			
		} else {	# Otherwise do normal static or normal looping animated
			for (my $i=0; $i<$frames; $i++) {
				my ($outfile);
				$outfile=$tmppath.$section.'-'.$i.'.png';
	
				print FH  "1 ".
				$cfg->val($section,'Hot spot x')." ".
				$cfg->val($section,'Hot spot y')." ".
				$outfile." ".
				$cfg->val($section,'Interval')."\n";
	
				
			}
		}

	if ($array > -1) {
		goto LOOP;
	}
}

print "Writing theme index file.\n";
open (FH, "> ${path}index.theme");
print FH <<EOF;
[Icon Theme]
Name=$name
Example=left_ptr
Inherits=$inherits
EOF
close (FH);

my $dummy;

if (!$nozip){
	$dummy = `tar cf $name.tar $name; gzip $name.tar;`;
	print "Theme zipped into $name.tar.gz\n";
}

if ($install){
	$dummy = `mkdir -p ~/.icons; cp -Rp $name ~/.icons/;`;
	print "Theme installed into ~/.icons/\n";
}

if (!$keeptemp){
	$dummy = `rm -r $tmppath`;
	print "Removed temp directory $tmppath\n";
}


print "Theme written to ${path}\n";
print "Done.\n";











