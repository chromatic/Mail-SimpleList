#!/usr/bin/perl -w

use strict;

my $alias_dir = '/home/alias/aliases';

die "Alias directory '$alias_dir' does not exist\n" unless -d $alias_dir;

use Mail::SimpleList;
Mail::SimpleList->new( $alias_dir )->process();
