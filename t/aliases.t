#!/usr/bin/perl -w

BEGIN
{
	chdir 't' if -d 't';
	use lib '../lib', '../blib/lib';
}

use strict;

use Cwd;
use File::Path;
use File::Spec;

use Test::More tests => 25;
use Test::Exception;
use Test::MockObject;

use_ok( 'Mail::SimpleList::Aliases' ) or exit;
can_ok( 'Mail::SimpleList::Aliases', 'new' );

$ENV{HOME}  = cwd();

my $aliases = Mail::SimpleList::Aliases->new();
isa_ok( $aliases, 'Mail::SimpleList::Aliases' );

my $alias_dir = File::Spec->catdir( $ENV{HOME}, '.aliases' );

can_ok( $aliases, 'alias_dir' );
is( $aliases->alias_dir(), $alias_dir,
	'new() should use ~/.aliases directory as default' );

is( Mail::SimpleList::Aliases->new( $ENV{HOME} )->alias_dir(), $ENV{HOME},
	'... or a specified directory' );

can_ok( $aliases, 'exists' );

{
	mkpath( File::Spec->catdir( $alias_dir ) );

	my $foo_file = File::Spec->catfile( $alias_dir, 'foo.sml' );
	local *FOO;
	open( FOO, '>' . $foo_file );
	print FOO 'test';

	link $foo_file, File::Spec->catfile( $alias_dir, '12345.sml' );
}

ok( $aliases->exists( 'foo' ),     'exists() should be true if alias exists' );
ok( $aliases->exists( 12345 ),     '... or if alias is a link' );
ok( ! $aliases->exists( 'unfoo' ), '... false otherwise' );

can_ok( $aliases, 'create' );
my $new_alias = $aliases->create( 'chromatic@wgz.org' );
isa_ok( $new_alias, 'Mail::SimpleList::Alias' );

is( @{ $new_alias->members() }, 1,
	'create() should create a new alias with the owner as the only member' );
is( $new_alias->members()->[0], 'chromatic@wgz.org',
	'... and the right member' );
is( $new_alias->owner(), 'chromatic@wgz.org', '... and the right owner' );
$aliases->save( $new_alias, 'newalias' );

can_ok( $aliases, 'fetch' );

my $alias = $aliases->fetch( 'newalias' );
isa_ok( $alias, 'Mail::SimpleList::Alias' );

ok( @{ $alias->members() }, 'fetch() should return a populated alias' );
is(    $alias->owner(),     'chromatic@wgz.org', '... with the right data' );
is(    $alias->name(),      'newalias',          '... including the name' );

can_ok( $aliases, 'alias_file' );
is( $aliases->alias_file( 'foo' ),
	File::Spec->catfile( $ENV{HOME}, '.aliases','foo.sml' ),
	'alias_file() should return valid alias filepath' );
{
	local $aliases->{alias_dir} = 'newdir/';
	is( $aliases->alias_file( 'bar' ), 'newdir/bar.sml',
		'... respecting alias dir' );
}

can_ok( $aliases, 'save' );
$alias->{members} = [qw( foo bar baz )];
$aliases->save( $alias, 'newalias' );
$alias = $aliases->fetch( 'newalias' );
is( @{ $alias->members() }, 3, 'save() should save existing alias' );

END
{
	rmtree( File::Spec->catdir( $ENV{HOME}, '.aliases' ) );
}
