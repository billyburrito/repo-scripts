#!/usr/bin/perl
# a simple script to remove extraneous files out of a yum style repository

use Data::Dumper;
use XML::Simple;

use strict;

my @source = `find /repo/centos/5 -name primary.xml.gz`;
#my @source = `find /repo/centos/5/ -name primary.xml.gz`;
#my @source = '/repo/centos/5/addons/i386/repodata/primary.xml.gz';

for my $xml ( @source ) {
    
    # strip off the trailing new line for each xml file found
    chomp $xml;
    
    # open up the xml file and dump it to a data structure
    my $output = `zcat $xml`;
    my $xml_href = XMLin($output, ForceArray => 1);
    
    # trim the path relative to where we are
    $xml =~ s/repodata\/primary.xml.gz//;

    # init the hrefs we will use to push data into
    my $valid_files;
    my $all_files;

    # extract the file locations from the xml data
    if ( $xml_href->{package} ) {
        for my $index ( 0..( (scalar @{$xml_href->{package}}) - 1 ) ){
            # append the path to the front of the file
            $valid_files->{$xml .  $xml_href->{package}->[$index]->{location}->[0]->{href}} = 1;
        }
    }

    # get a listing of rpms in the path we are working in
    my @find_output = `find $xml -name *.rpm`;

    # push the file names into a data structure to compare them 
    for my $line (@find_output) {
        chomp $line;
        $all_files->{$line} = 1;
    }

    # delete valid files from all files, $all_files will contain just extra
    # files now
    for my $files ( keys %{$valid_files} ) {
        if ($all_files->{$files}) {
            delete $all_files->{$files};
        }
    }

    # delete whatever files show up in $all_files
    for my $delete ( keys %{$all_files} ) {
        unlink $delete;
    }

    my $delete_count = scalar keys %{$all_files};
    print $delete_count . " extraneous files have been deleted from $xml\n";
}
