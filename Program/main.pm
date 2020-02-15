package main ;

use strict ;
use warnings ;

use UserConfig ;
use ProgConfig ;

require Exporter ;
our @ISA = qw(Exporter) ;
our @EXPORT = qw(main);


#############################################################################################
# VARIABLES

my @parts ;
my %known_parts ;


my $string_part_config_behavior_scale ;
my $string_part_config_behavior ;
my $string_part_config_scale ;
my $string_part_config ;         

#############################################################################################
# FUNCTIONS FOR CFG FILES

sub getCFGFile
# Arg 1 is full path name to a Template CFG file
{
    my $file = shift ;

    open (my $fh, $file) or die "Cannot open config file $file" ;
#    open (my $fh, "./" . $file) or die "Cannot open config file $file" ;
    my @content = <$fh> ;
    my $s = join ("", @content) ;
    close $fh ; 

    return $s ;
} # getCFGFile()


#############################################################################################
# AUX FUNCTIONS

sub getNormalizedSize
# Arg 1 is scalar from 
{
    my $arg = shift ;

    #printf("%s-%s\n", $arg, $EXISTING_SIZES{$arg}) ;
    return ( defined $arg ? $EXISTING_SIZES{$arg} : undef ) ;
}

sub getScaleBehaviorFromPart
# Arg is $h from foreach my $h (@parts)
{
    my $h = shift ;
    my $name = $h->{part_name} ;
    my $behavior = undef ;


    if ($name =~ /srb/)
    {
        $behavior = "SRB" ;
    }
    elsif ($name =~ /engine/)
    {
        $behavior = "Engine" ;   
    }
    elsif ($name =~ /decoupler|separator/)
    {
        $behavior = "Decoupler" ;   
    }
    elsif ($name =~ /science|goo|materialbay/)
    {
        $behavior = "Science" ;   
    }
    else
    {
        $behavior = "none" ;
    }
    return $behavior ;
} # --- getBehaviorFromPart() ---


sub getScaleMethodFromPart
# Arg is $h from foreach my $h (@parts)
{
    my $h = shift ;
    my $item = $h->{item} ;

    foreach my $i ( @PREFERED_SCALE_METHOD )
    {
        my @k = keys %{$i} ;
        my $scale_entry = shift @k ;

        if ( $h->{item} =~ /$scale_entry/ )
        # Found a matching
        {
            return $i->{$scale_entry} ;
        }
    }
}  # --- getScaleMethodFromPart() ---

sub readAddOnFolder
# Arg is a valid path to a mod part folder
{
    my $pdir = shift ;

    opendir(my $dh, $pdir) || die "Can't opendir $pdir: $!";
    my @entries = grep { /^(?!\..*)/ && ((-d "$pdir/$_") || ( /\.cfg$/ )) } readdir($dh);
    closedir $dh;

    my ($mod_name) = $pdir =~ m/.*\/(.+)\/Parts/ ;

    foreach (@entries)
    {
        if ( -d "$pdir/$_" )
        # Go deeper
        {
            readAddOnFolder("$pdir/$_") ;
        }
        else
        # Process .cfg part file
        {
            my $part_is_radial = 0 ;

            open(my $fh, "$pdir/$_") || die "Can't open $pdir/$_: $!" ;
            my @lines = <$fh> ;
            close ($fh) ;
            chomp(@lines) ;


            # loop on all lines until name has been found
            my $line = "" ;
            my $part_found = 0 ;
            my $finished = 0 ;
            my $part_description = "" ; # such as "// 2x size static ladder"
            my $part_name        = "" ; # such as "  name = restock-ladder-static-2"

            until ( $finished )
            {
                $line = shift @lines ;
                
                ($line =~ m/ReStock\+/) && next ;
                ($line =~ m/NOTE:/)     && next ;
                ( length($line) <2 ) && next ;
                ($line =~ m/PART/)      && do { $part_found = 1 ; next ;} ;


                (!$part_found) && do { $part_description = $part_description . $line ; next ;} ;
                
                # Here PART line has been found - remove spaces
                $line =~ s/[\n\r\s]+//g ;
               
                if ($line =~ m/name=/)
                {
                    ($part_name) = $line =~ /.*=(.*)/ ; # take the right part from =
                    $finished = 1 ;
                }   
            }

            my ($item, $part_size1, $part_size2, $part_variant) = $part_name =~ /^restock-(.*)-(\d+)-(\d+)-(\d+)$/ ;

            if ( !defined $item )
            {
                ($item, $part_size1, $part_variant) = $part_name =~ /^restock-(.*)-(\d+)-(\d+)$/ ;
                $part_size2 = -1 ;
            }
            if ( !defined $item )
            {
                ($item, $part_variant) = $part_name =~ /^restock-(.*)-(\d+)$/ ;
                $part_size1 = -1 ;
                $part_size2 = -1 ;

                # we may encounter parts looking like [...]/ReStockPlus/Parts/Coupling/1875/restock-decoupler-1875-truss-1
                # OR
                # Last chance to get a size from the path
                my ($oside) = $pdir =~ /.*\/([^\/]+)/ ;
                printf("---DEBUG LAST CHANCE partname=%s ; oside=%s---\n", $part_name, $oside) ;
                $part_size1     = ($oside =~ m/\d+/    ? $oside : -1) ; # May inlude radial
                printf("---DEBUG SIZE %d\n", $part_size1) ;
            }
            if ( !defined $item )
            {
                # Example here we have a part [...]/ReStockPlus/Parts/Engine/125/restock-engine-125-valiant
                # item is engine-125-valiant
                ($item) = $part_name =~ /^restock-(.*)$/ ;
                #printf("---DEBUG pdir/partname=%s%s---\n", $pdir, $part_name) ;
 
                # oside is 125
                my ($oside) = $pdir =~ /.*\/([^\/]+)/ ;
                #printf("---DEBUG item=%s ; oside=%s---\n", $item, $oside) ;

                $part_is_radial = ($oside =~ m/radial/ ? 1      :  0) ;
                $part_size1     = ($oside =~ m/\d+/    ? $oside : -1) ; # May inlude radial
                $part_size2     = -1 ;
            } 

            # Check whether this part has already been loaded or not
            # Anvil bug being declared twice for <= 1.7.3 and 1.8+
            (defined $known_parts{$part_name}) && do { next ;} ;

            # Last check on part name to detect a radial part
            if ($item =~ m/radial/)
            {
               $part_is_radial = 1 ;
            }

            $known_parts{$part_name} = $part_name ;

            my $struct = {
                part_name        => $part_name,
                part_description => $part_description,
                item             => $item,
                part_size1       => getNormalizedSize($part_size1),
                part_size2       => getNormalizedSize($part_size2),
                part_variant     => $part_variant,
                path             => $pdir,
                part_is_radial   => $part_is_radial,
                scale_method     => undef,
                scale_behavior   => undef,
                mod_name         => $mod_name,
                is_ignored       => 0,
            } ;

            # Back listed item : docking ports, fairings.
            if ( $item =~ /dock|fairing|ladder/ )
            {
                $struct->{is_ignored} = 1 ;             
            }
            push @parts, $struct ;
        }
    }
} # --- readAddOnFolder() ---



sub parse
{
	# We are going to parse all addons defined in _CONFIG => _ADD_ONS
    readAddOnFolder _RESTOCKPLUS_PART_PATH ;
    readAddOnFolder _RESTOCKRIGIDLEGS_PART_PATH ;
} # --- parse() ---

sub process
{
    foreach my $h (@parts)
    {
        $h->{scale_method}   = getScaleMethodFromPart($h) ;
        $h->{scale_behavior} = getScaleBehaviorFromPart($h) ;
    }
} # --- process() ---


sub writeCFG
{ 
    open (my $fh, ">" . _TS_CFG_OUTDIR . "/" . _TS_CFG_OUTFILE) or die "KAPUT FILE @!" ;
    open (my $fhtest, ">" . _TS_CFG_OUTDIR . "/" . _TS_CFG_OUTFILE . ".test.csv") or die "KAPUT FILE @!" ;


    print $fh "// Tweakscale File for Restockplus & Rigid legs\n" ;
    print $fh "// BETA VERSION USE AT YOUR OWN RISKS - version " . _PROG_VERSION . "\n" ;
    print $fh "// xot1643\@Github\n" ;
    print $fh "// To be placed in <KSP ROOT>/GameData/TweakScale/patches\n\n" ;
    print $fh "// Notes :\n" ;
    print $fh "// ---------------------------------------\n" ;
    print $fh "// Docking ports, fairing and ladders are ignored as they already are for stock parts in Tweakscale \n" ;
    print $fh "// Docking ports : seems to be a very bas idea to resize them.\n" ;
    print $fh "// Fairings : scaling is ok AFTER building them, are buggy if scaled BEFORE building them.\n" ;
    print $fh "// Ladders  : dunno but seems to be a bad idea as well.\n\n" ;


    foreach my $h (@parts)
    {
        my $string_to_write ;

        # Size is defined, a behavior has been identified,  
        if ( ($h->{scale_behavior} ne "none") && ($h->{part_size1} != -1) )
        {
            $string_to_write = $string_part_config_behavior_scale ;
            $string_to_write =~ s/__BEHAVIOR__/$h->{scale_behavior}/g ;
            $string_to_write =~ s/__SIZE__/$h->{part_size1}/g ;
        }
        elsif ( ($h->{scale_behavior} ne "none") && ($h->{part_size1} == -1) )
        {
            $string_to_write = $string_part_config_behavior ;
            $string_to_write =~ s/__BEHAVIOR__/$h->{scale_behavior}/g ;
        }
        elsif ( ($h->{scale_behavior} eq "none") && ($h->{part_size1} != -1) )
        {
            $string_to_write = $string_part_config_scale ;
            $string_to_write =~ s/__SIZE__/$h->{part_size1}/g ;
        }
        else
        # ($$h{scale_behavior} eq "none") && ($$h{part_size1} == -1)
        {
            $string_to_write = $string_part_config ;
        }
        $string_to_write =~ s/__MODNAME__/$h->{mod_name}/g ;
        $string_to_write =~ s/__PARTNAME__/$h->{part_name}/g ;
        $string_to_write =~ s/__PARTDESC__/$h->{part_description}/g ;
        $string_to_write =~ s/__SCALETYPE__/$h->{scale_method}/g ;

        if ( $h->{is_ignored} )
        {
            $string_to_write = "// Filtered part\n" . $string_to_write ;
            $string_to_write =~ s/\R/\n\/\/ /g ;
        }
        print $fh $string_to_write . "\n" ;

        print $fhtest join (";", $h->{mod_name}, $h->{part_name}, $h->{part_description}, $h->{scale_method}, $h->{scale_behavior}, $h->{part_size1}, $h->{is_ignored},"\n") ;

    }

    close $fh ;
    close $fhtest ;
} # --- writeCFG() ---


sub main
{
   # Load Templates for TS part config
   $string_part_config_behavior_scale = getCFGFile(_PART_CFG_SCALEBEHAVIOR) ;
   $string_part_config_behavior       = getCFGFile(_PART_CFG_BEHAVIOR) ;
   $string_part_config_scale          = getCFGFile(_PART_CFG_SCALE) ;
   $string_part_config                = getCFGFile(_PART_CFG_NONE) ; 	

   printf("coucou\n") ;
   parse ;
   process ;
   writeCFG ; 
}

1;