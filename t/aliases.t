#!/usr/bin/perl -w

BEGIN
{
	chdir 't' if -d 't';
	unshift @INC, '../lib', '../blib/lib';
}

use strict;

use Cwd;
use File::Path;
use File::Spec;

use Test::More tests => 26;
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
my $new_alias = $aliases->create( 'newalias', 'chromatic@wgz.org' );
isa_ok( $new_alias, 'Mail::SimpleList::Alias' );

is( @{ $new_alias->members() }, 1,
	'create() should create a new alias with the owner as the only member' );
is( $new_alias->members()->[0], 'chromatic@wgz.org',
	'... and the right member' );
is( $new_alias->owner(), 'chromatic@wgz.org', '... and the right owner' );
ok( $aliases->exists( 'newalias' ),           '... saving the alias' );
ok( ! $aliases->create( 'newalias' ), '... returning false if alias exists' );

can_ok( $aliases, 'fetch' );

my $alias = $aliases->fetch( 'newalias' );
isa_ok( $alias, 'Mail::SimpleList::Alias' );

ok( @{ $alias->members() }, 'fetch() should return a populated alias' );
is(    $alias->owner(),     'chromatic@wgz.org', '... with the right data' );

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
is( @{ $alias->members }, 3, 'save() should save existing alias' );

END
{
	rmtree( File::Spec->catdir( $ENV{HOME}, '.aliases' ) );
}

__END__
isa_ok( $aliases->{Audit}, 'Mail::Audit' );
ok( exists $aliases->{aliases}, 'new() should open aliases file, if it exists' );
is( $aliases->{alias_file}, 'aliases', '... storing the file name' );

throws_ok { Mail::SimpleList::Aliases->new() } qr/No alias file given/,
	'new() should die given no alias file';

throws_ok { Mail::SimpleList::Aliases->new( 'notafile' ) } qr/No 'notafile'/,
	'... or if alias file cannot be read';

for my $command (qw( help new unsubscribe ))
{
	$result = $aliases->find_command();
	ok( $result, "... but true for valid command '$command'" );
	is( $result, "command_$command", '... with proper method name' );
}

can_ok( $aliases, 'process' );
my $process = \&Mail::SimpleList::Aliases::process;
$mock->set_series( find_command => 0, 'command_foo' )
	 ->set_true( 'command_foo' )
	 ->set_series( handle_command => 0, 1 )
	 ->set_series( find_alias => 0, 0, 1 )
	 ->set_true( 'reject' )
	 ->set_true( 'deliver' )
	 ->clear();

$result = $process->( $mock );
is( $mock->next_call(), 'find_command', 'process() should check for command' );
my $method = $mock->next_call();
isnt( $method, 'command_foo', '... not calling command if not present' );

$mock->clear();
$result = $process->( $mock );
$method = $mock->next_call( 2 );
is( $method, 'command_foo', '... but calling it if it is' );

$result = $process->( $mock );
is( $mock->next_call( 2 ), 'find_alias', '... looking for alias' );
$method = $mock->next_call();
is( $method, 'reject', '... rejecting without a valid alias' );

$mock->clear();
$result = $process->( $mock );

is( $mock->next_call( 3 ), 'deliver', '... but delivering if alias is okay' );

can_ok( $aliases, 'deliver' );
my $body = [];
$mock->set_always( body => $body )
	 ->set_true( 'smtpsend' )
	 ->set_always( head => $mock )
	 ->set_true( 'add' )
	 ->set_always( to => 'sml@snafu' )
	 ->clear();

$mock->{aliases}{12345} = [qw( foo bar baz quux )];

{
	# avoid latent T::MO bug with add()
	local *Test::MockObject::add;
	$aliases->deliver( 12345 );
}

like( "@$body", qr/To unsubscribe:/,
	'deliver() should add unsubscribe message' );

$method = $mock->next_call( 2 );
is( $method, 'to', '... fetching alias address' );
$method = $mock->next_call();
is( $method, 'head', '... fetching header' );

($method, my $args) = $mock->next_call();
is( $method, 'add', '... adding Reply-To address' );
is( "@$args[1, 2]", 'Reply-To: sml@snafu', '... set to list address' );

($method, $args) = $mock->next_call( );
is( $method, 'smtpsend', '... sending message' );
is( $args->[1], 'Bcc', '... blind carbon copying recipients' );
is_deeply( $args->[2], [ keys %{ $aliases->{aliases}{12345} } ], '... for list' );
is( "@$args[3, 4]", 'To ', '... setting To to blank' );

can_ok( $aliases, 'reject' );
throws_ok { $aliases->reject() } qr/Invalid alias/, 'reject() should throw error';
cmp_ok( $!, '==', 100, '... and should set ERRNO to REJECTED' );

can_ok( $aliases, 'load_aliases' );
# tested in new()

can_ok( $aliases, 'save_aliases' );
my $new_aliases   = { foo => 1, bar => { baz => [ 'quux', 'quack' ] } };
$aliases->{aliases}    = $new_aliases;
$aliases->{alias_file} = 'new_aliases';

copy( 'aliases', 'new_aliases' );

$aliases->save_aliases();
$aliases->load_aliases( 'new_aliases' );
is_deeply( $aliases->{aliases}, $new_aliases,
	'save_aliases() should save restorable alias file' );
 
$aliases->{alias_file} = '..';
throws_ok { $aliases->save_aliases() } qr/Cannot write '..':/,
	'... and should die if it cannot write the file';

can_ok( $aliases, 'command_new' );
my $aliases = { 'foo@bar.com' => 1, baz => 1 };
$mock->set_always( body => [ keys %$aliases ] )
	 ->set_always( to   => 'sml+21@snafu.org' )
	 ->set_true( 'reply' )
	 ->clear();
{
	local *Mail::SimpleList::Aliases::save_aliases;
	*Mail::SimpleList::Aliases::save_aliases = sub { 1 };
	$result = $aliases->command_new();
}
ok( $result, 'command_new() should create and return new alias' );
ok( exists $aliases->{aliases}{$result}, '... populating alias list' );
is_deeply( $aliases->{aliases}{$result}, $aliases, '... with aliases from body' );

($method, $args) = $mock->next_call( 3 );
is( $method, 'reply', '... and should reply to sender' );
is( $args->[1], 'body', '... setting a mail body' );
like( $args->[2], qr/Mailing list created.  Post to sml\+$result\@snafu/,
	'... with list address' );

can_ok( $aliases, 'command_help' );

can_ok( $aliases, 'command_unsubscribe' );

$mock->set_series( from => 'foo@bar', 'baz@bar' )
	 ->set_series( find_alias => 'bleargh', 'blah' )
	 ->set_true( 'reply' )
	 ->set_true( 'save_aliases' )
	 ->mock( remove_address => sub { $aliases->remove_address( @_[1, 2] ) } )
	 ->clear();

$mock->{Audit} = $mock;

$aliases->{aliases} = {
	bleargh => { map { $_ => 1 } qw( foo bar baz ) },
	blah    => { map { $_ => 1 } 'baz@bar', 'foo@bar' },
};

my $unsub = \&Mail::SimpleList::Aliases::command_unsubscribe;
$unsub->( $mock );

is( $mock->next_call(), 'find_alias',
	'command_unsubscribe() should fetch alias' );
is( $mock->next_call(), 'from', '... and sender' );
is( keys %{ $aliases->{aliases}{bleargh} }, 3,
	'... removing no aliases if sender not in alias' );

($method, $args) = $mock->next_call( 2 );
is( $method, 'reply', '... replying to sender' );
is( "@$args[1, 2]",
	'body Unsubscribe unsuccessful for foo@bar.  Check the address.',
	'... with a failure message' );

{
	local *Mail::SimpleList::Aliases::save_aliases;
	*Mail::SimpleList::Aliases::save_aliases = sub { $result = 'saved' };
	$unsub->( $mock );
}
is_deeply( $aliases->{aliases}{blah}, { 'foo@bar' => 1 },
	'... removing the address from the alias if the sender is in the list' );
is( $result, 'saved', '... saving the aliases' );

END
{
	1 while unlink 'new_aliases';
}
