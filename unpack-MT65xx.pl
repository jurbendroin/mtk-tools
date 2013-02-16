#!/usr/bin/perl

#
# script from Android-DLS WiKi
#
# changes by Bruno Martins:
#   - modified to work with MT6516 boot and recovery images (17-03-2011)
#   - included support for MT65x3 and eliminated the need of header files (16-10-2011)
#   - included support for MT65xx logo images (31-07-2012)
#   - fixed problem unpacking logo images containing more than nine packed rgb565 raw files (29-11-2012)
#   - re-written logo images file verification (29-12-2012)
#   - image resolution is now calculated and shown when unpacking logo images (02-01-2013)
#   - added colored screen output (04-01-2013)
#   - included support for logo images containing uncompressed raw files (06-01-2013)
#   - more verbose output when unpacking boot and recovery images (13-01-2013)
#   - kernel or ramdisk extraction only is now supported (13-01-2013)
#   - re-written check of needed binaries (13-01-2013)
#   - ramdisk.cpio.gz deleted after successful extraction (15-01-2013)
#

use strict;
use warnings;
use bytes;
use File::Path;
use Compress::Zlib;
use Term::ANSIColor;
use Scalar::Util qw(looks_like_number);

my $version = "MTK-Tools by Bruno Martins\nMT65xx unpack script (last update: 20-01-2013)\n";
my $usage = "unpack-MT65xx.pl <infile> [COMMAND ...]\n  Unpacks boot, recovery or logo image\n\nOptional COMMANDs are:\n\n  -kernel_only\n    Extract kernel only from boot or recovery image\n\n  -ramdisk_only\n    Extract ramdisk only from boot or recovery image\n\n  -force_logo_res <width> <height>\n    Forces logo image file to be unpacked by specifying image resolution,\n    which must be entered in pixels\n     (only useful when no zlib compressed images are found)\n\n";

print colored ("$version", 'bold blue') . "\n";
die "Usage: $usage" unless $ARGV[0];

if ( $ARGV[1] ) {
	if ( $ARGV[1] eq "-kernel_only" || $ARGV[1] eq "-ramdisk_only" ) {
		die "Usage: $usage" unless !$ARGV[2];
	} elsif ( $ARGV[1] eq "-force_logo_res" ) {
		die "Usage: $usage" unless looks_like_number($ARGV[2]) && looks_like_number($ARGV[3]) && !$ARGV[4];
	} else {
		die "Usage: $usage";
	}
}

my $inputfile = $ARGV[0];

open (INPUTFILE, "$inputfile") or die colored ("Error: could not open the specified file '$inputfile'", 'red') . "\n";
my $input;
while (<INPUTFILE>) {
	$input .= $_;
}
close (INPUTFILE);

if ((substr($input, 0, 4) eq "\x88\x16\x88\x58") & (substr($input, 8, 4) eq "LOGO")) {
	# if the input file contains the logo signature, try to unpack it
	print "Valid logo signature found...\n";
	if ( $ARGV[1] ) {
		die colored ("\nError: $ARGV[1] switch can't be used with logo images", 'red') . "\n"
			if ($ARGV[1] ne "-force_logo_res");
	}
	unpack_logo($input);
} elsif (substr($input, 0, 7) eq "\x41\x4e\x44\x52\x4f\x49\x44") {
	# else, a valid Android signature is found, try to unpack boot or recovery image
	print "Valid Android signature found...\n";
	if ( $ARGV[1] ) {
		die colored ("\nError: $ARGV[1] switch can't be used with boot or recovery images", 'red') . "\n"
			if ($ARGV[1] eq "-force_logo_res");
		$ARGV[1] =~ s/-//;
		$ARGV[1] =~ s/_only//;
		unpack_boot($input, $ARGV[1]);
	} else {
		unpack_boot($input, "kernel and ramdisk");
	}
} else {
	die colored ("Error: the input file does not appear to be supported or valid", 'red') . "\n";
}

sub unpack_boot {
	my ($bootimg, $extract) = @_;
	my ($bootMagic, $kernelSize, $kernelLoadAddr, $ram1Size, $ram1LoadAddr, $ram2Size, $ram2LoadAddr, $tagsAddr, $pageSize, $unused1, $unused2, $bootName, $cmdLine, $id) = unpack('a8 L L L L L L L L L L a16 a512 a8', $bootimg);

	print colored ("\nInput file information:\n", 'yellow') . "\n";
	print " Kernel size: $kernelSize bytes / ";
	printf ("load address: %#x\n", $kernelLoadAddr);
	print " Ramdisk size: $ram1Size bytes / ";
	printf ("load address: %#x\n", $ram1LoadAddr);
	print " Second stage size: $ram2Size bytes / ";
	printf ("load address: %#x\n", $ram2LoadAddr);
	print " Page size: $pageSize bytes\n ASCIIZ product name: '$bootName'\n";
	if ((substr($cmdLine, 0, 4) eq "\x00\x00\x00\x00")) {
		print " Command line: (none)\n\n";
	} else {
		print " Command line: $cmdLine\n\n";
	}
	
	if ( $extract eq "kernel" || $extract eq "kernel and ramdisk" ) {
		my($kernel) = substr($bootimg, $pageSize, $kernelSize);

		open (KERNELFILE, ">$ARGV[0]-kernel.img");
		binmode (KERNELFILE);
		print KERNELFILE $kernel or die;
		close (KERNELFILE);

		print "Kernel written to '$ARGV[0]-kernel.img'\n";
	}

	if ( $extract eq "ramdisk" || $extract eq "kernel and ramdisk" ) {
		my($kernelAddr) = $pageSize;
		my($kernelSizeInPages) = int(($kernelSize + $pageSize - 1) / $pageSize);

		my($ram1Addr) = (1 + $kernelSizeInPages) * $pageSize;

		my($ram1) = substr($bootimg, $ram1Addr, $ram1Size);

		# chop ramdisk header
		$ram1 = substr($ram1, 512);

		if (substr($ram1, 0, 2) ne "\x1F\x8B") {
			die colored ("\nError: the boot image does not appear to contain a valid gzip file", 'red') . "\n";
		}

		open (RAMDISKFILE, ">$ARGV[0]-ramdisk.cpio.gz");
		binmode (RAMDISKFILE);
		print RAMDISKFILE $ram1 or die;
		close (RAMDISKFILE);

		if (-e "$ARGV[0]-ramdisk") {
			rmtree "$ARGV[0]-ramdisk";
			print "Removed old ramdisk directory '$ARGV[0]-ramdisk'\n";
		}

		mkdir "$ARGV[0]-ramdisk" or die;
		chdir "$ARGV[0]-ramdisk" or die;
		foreach my $tool ("gzip", "cpio") {
			die colored ("\nError: $tool binary not found!", 'red') . "\n"
				if system ("command -v $tool >/dev/null 2>&1");
		}
		print "Ramdisk size: ";
		system ("gzip -d -c ../$ARGV[0]-ramdisk.cpio.gz | cpio -i");
		system ("rm ../$ARGV[0]-ramdisk.cpio.gz");

		print "Extracted ramdisk contents to directory '$ARGV[0]-ramdisk'\n";
	}

	print "\nSuccessfully unpacked $extract.\n";
}

sub unpack_logo {
	my $logobin = $_[0];
	my @resolution = (
		# HD (High-Definition)
		[360,640,"(nHD)"], [540,960,"(qHD)"], [720,1280,"(HD)"], [1080,1920,"(FHD)"],
		[1440,2560,"(WQHD)"], [2160,3840,"(QFHD)"], [4320,7680,"(UHD)"], 
		# VGA (Video Graphics Array)
		[120,160,"(QQVGA)"], [160,240,"(HQVGA)"], [240,320,"(QVGA)"],
		[240,400,"(WQVGA)"], [320,480,"(HVGA)"], [480,640,"(VGA)"],
		[480,800,"(WVGA)"], [480,854,"(FWVGA)"], [600,800,"(SVGA)"],
		[640,960,"(DVGA)"], [576,1024,"(WSVGA)"], [600,1024,"(WSVGA)"],
		# XGA (Extended Graphics Array)
		[768,1024,"(XGA)"], [768,1280,"(WXGA)"], [864,1152,"(XGA+)"],
		[900,1440,"(WXGA+)"], [1024,1280,"(SXGA)"], [1050,1400,"(SXGA+)"],
		[1050,1680,"(WSXGA+)"], [1200,1600,"(UXGA)"], [1200,1920,"(WUXGA)"], 
		# Quad XGA (Quad Extended Graphics Array)
		[1152,2048,"(QWXGA)"], [1536,2048,"(QXGA)"], [1600,2560,"(WQXGA)"],
		[2048,2560,"(QSXGA)"], [2048,3200,"(WQSXGA)"], [2400,3200,"(QUXGA)"], [2400,3840,"(WQUXGA)"],
		# Others (found in some MediaTek logo images)
		[38,54,""], [48,54,""], [135,24,""], [135,1,""]
	);

	# get logo header
	my $header = substr($logobin, 0, 512);
	my ($header_sig, $logo_length, $logo_sig) = unpack('a4 V A4', $header);

	# throw a warning if logo file size is not what is expected
	# (it may happen if logo image was created with a backup tool and contains trailing zeros)
	my $sizelogobin = -s $inputfile;
	if ($logo_length != $sizelogobin - 512) {
		print colored ("Warning: unexpected logo image file size! Trying to unpack it anyway...", 'yellow') . "\n";
	}

	# chop the header and any eventual garbage found at the EOF
	# (only extract important logo information that contains packed raw images)
	my $logo = substr($logobin, 512, $logo_length);

	# check if logo length is really consistent
	if ( length ($logo) != $logo_length ) {
		die colored ("\nError: no way, the logo image file seems to be corrupted", 'red') . "\n";
	}

	if (-e "$ARGV[0]-unpacked") {
		rmtree "$ARGV[0]-unpacked";
		print "\nRemoved old unpacked logo directory '$ARGV[0]-unpacked'\n";
	}

	mkdir "$ARGV[0]-unpacked" or die;
	chdir "$ARGV[0]-unpacked" or die;
	print "Extracting raw images to directory '$ARGV[0]-unpacked'\n";

	# get the number of packed raw images
	my $num_blocks = unpack('V', $logo);

	if ( ! $num_blocks ) {
		die "\nNo zlib packed rgb565 images were found inside logo file." . 
		    "\nRecheck script usage and try to use -force_logo_res switch.\n" unless $ARGV[1];

		# if no compressed files are found, try to unpack logo based on specified image resolution
		my $image_file_size = ($ARGV[2] * $ARGV[3] * 2);
		$num_blocks = $logo_length / $image_file_size;

		print "\nNumber of uncompressed images found (based on specified resolution): $num_blocks\n";
		
		for my $i (0 .. $num_blocks - 1) {
			my $filename = sprintf ("%s-img[%02d]", $ARGV[0], $i);

			open (RAWFILE, ">$filename.rgb565");
			binmode (RAWFILE);
			print RAWFILE substr($logo, $i * $image_file_size, $image_file_size) or die;
			close (RAWFILE);
			print "Raw image #$i written to '$filename.rgb565'\n";
		}
	} else {
		my $j = 0;
		my (@raw_addr, @zlib_raw) = ();
		print "\nNumber of raw images found: $num_blocks\n";
		# get the starting address of each raw file
		for my $i (0 .. $num_blocks - 1) {
			$raw_addr[$i] = unpack('L', substr($logo, 8+$i*4, 4));
		}
		# extract rgb565 raw files (uncompress zlib rfc1950)
		for my $i (0 .. $num_blocks - 1) {
			if ($i < $num_blocks-1) {
				$zlib_raw[$i] = substr($logo, $raw_addr[$i], $raw_addr[$i+1]-$raw_addr[$i]);
			} else {
				$zlib_raw[$i] = substr($logo, $raw_addr[$i]);
			}
			my $filename = sprintf ("%s-img[%02d]", $ARGV[0], $i);

			open (RAWFILE, ">$filename.rgb565");
			binmode (RAWFILE);
			print RAWFILE uncompress($zlib_raw[$i]) or die;
			close (RAWFILE);
		
			print "Raw image #$i written to '$filename.rgb565'\n";
			# calculate rgb565 image resolution
			my $raw_num_pixels = length (uncompress($zlib_raw[$i])) / 2;
			while ( $j <= $#resolution ) {
				last if ( $raw_num_pixels == ($resolution[$j][0] * $resolution[$j][1]) );
				$j++;
			}
			if ( $j <= $#resolution ) {
				print "  Image resolution (width x height): $resolution[$j][0] x $resolution[$j][1] $resolution[$j][2]\n";
				print "  Convert raw image to png \n";
				system ("ffmpeg -vcodec rawvideo -f rawvideo -pix_fmt rgb565 -s $resolution[$j][0]x$resolution[$j][1] -i $filename.rgb565 -f image2 -vcodec png $filename.png;");
			} else {
				print "  Image resolution: unknown\n";
			}
			$j = 0;
		}
	}

	print "\nSuccessfully extracted all images.\n";
}
