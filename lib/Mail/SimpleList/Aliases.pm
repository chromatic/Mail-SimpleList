package Mail::SimpleList::Aliases;

use strict;

use YAML;
use File::Path;
use File::Spec;

use Carp  'croak';
use Fcntl ':flock';

use Mail::SimpleList::Alias;

use vars qw( $VERSION );
$VERSION = '0.70';

sub new
{
	my ($class, $directory) = @_;
	$directory ||= File::Spec->catdir( $ENV{HOME}, '.aliases' );
	
	bless { alias_dir => $directory }, $class;
}

sub alias_dir
{
	my $self = shift;
	return $self->{alias_dir};
}

sub alias_file
{
	my ($self, $alias) = @_;
	return File::Spec->catfile( $self->alias_dir(), $alias . '.sml' );
}

sub exists
{
	my ($self, $alias) = @_;
	return -e $self->alias_file( $alias );
}

sub fetch
{
	my ($self, $alias) = @_;

	local *IN;
	open(  IN, $self->alias_file( $alias ) ) or return;
	flock( IN, LOCK_SH );
	my $data = do { local $/; <IN> };
	close IN;

	return Mail::SimpleList::Alias->new(%{ Load( $data ) });
}

sub create
{
	my ($self, $alias_name, $owner) = @_;
	return if $self->exists( $alias_name );

	my $alias = Mail::SimpleList::Alias->new();
	$alias->owner( $owner );
	$self->save( $alias, $alias_name );

	return $alias;
}

sub save
{
	my ($self, $alias, $alias_name) = @_;
	my $file = $self->alias_file( $alias_name );

	local *OUT;

	if (-e $file)
	{
		open( OUT, '+< ' . $file ) or croak "Cannot save data for '$file': $!";
		flock    OUT, LOCK_EX;
		seek     OUT, 0, 0;
		truncate OUT, 0;
	}
	else
	{
		open( OUT, '> ' . $file ) or croak "Cannot save data for '$file': $!";
	}

	print OUT Dump { %$alias };
}

1;

__END__

=head1 NAME

Mail::SimpleList::Aliases - manages Mail::SimpleList::Alias objects

=head1 SYNOPSIS

	use Mail::SimpleList::Aliases;
	my $aliases = Mail::SimpleList::Aliases->new( '.aliases' );

=head1 DESCRIPTION

Mail::SimpleList::Aliases manages the creation, loading, and saving of
Mail::SimpleList::Alias objects.  If you'd like to change how these objects are
managed on your system, subclass or reimplement this module.

=head1 METHODS

=over 4

=item * new( [ $alias_directory ] )

Creates a new Mail::SimpleList::Aliases object.  The single argument is
optional but highly recommended.  It should be the path to where Alias data
files are stored.  Beware that in filter mode, relative paths can be terribly
ambiguous.

If no argument is provided, this will default to C<~/.aliases> for the invoking
user.

=item * alias_dir()

Returns the directory where this object's Alias data files are stored.

=item * exists( $alias_id )

Returns true or false if an alias with this id exists.

=item * fetch( $alias_id )

Creates and returns a Mail::SimpleList::Alias object representing this alias
id.  This can return nothing if the alias does not exist.

=item * create( $alias_name, $owner )

Creates and returns a new Mail::SimpleList::Alias object, setting the owner and
saving the object.  If an alias of this name already exists, it will return
nothing.

=item * save( $alias, $alias_name )

Saves a Mail::SimpleList::Alias object provided as C<$alias> with the given
name in C<$alias_name>.

=back

=head1 AUTHOR

chromatic, C<chromatic@wgz.org>, with helpful suggestions from friends, family,
and peers.

=head1 BUGS

None known.

=head1 TODO

No plans.  It's pretty nice as it is.

=head1 COPYRIGHT

Copyright (c) 2003, chromatic.  All rights reserved.  This module is
distributed under the same terms as Perl itself.  Convenient for you!
