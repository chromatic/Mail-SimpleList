package Mail::SimpleList;

use strict;
my $pod = do { local $/; <DATA> };

use Carp  'croak';
use Fcntl ':flock';

use Mail::Mailer;
use Mail::Address;
use Mail::Internet;
use Mail::SimpleList::PodToHelp;

use Mail::SimpleList::Aliases;

use vars qw( $VERSION );
$VERSION = '0.80';

sub new
{
	my ($class, $alias_dir, $fh) = @_;
	$fh ||= \*STDIN;

	my $self =
	{
		Aliases => Mail::SimpleList::Aliases->new( $alias_dir ),
		Message => Mail::Internet->new( $fh ),
	};
	bless $self, $class;
}

sub fetch_alias
{
	my $self  = shift;
	my $alias = $self->parse_alias( $self->{Message}->get( 'to' ) );
	return unless $self->{Aliases}->exists( $alias );

	return wantarray ?
		( $self->{Aliases}->fetch( $alias ), $alias ) :
		$self->{Aliases}->fetch( $alias );
}

sub parse_alias
{
	my ($self, $address) = @_;
	my ($add) = Mail::Address->parse( $address );
	my $user  = $add->user();

	return ( $user =~ /\+([^+]+)$/ ) ? $1 : '';
}

sub command_help
{
	my $self   = shift;
	my $from   = $self->address_field( 'from' );
	my $parser = Mail::SimpleList::PodToHelp->new();

	$parser->output_string( \( my $output ));
	$parser->parse_string_document( $pod );

	$output =~ s/(\A\s+|\s+\Z)//g;

	$self->reply({ To => $from, Subject => 'Mail::SimpleList Help' },
		$output );
}

sub command_new
{
	my $self   = shift;
	my $from   = $self->address_field( 'from' );
	my $alias  = $self->{Aliases}->create( $from );
	my $users  = $self->process_body( $alias, @{ $self->{Message}->body() } );
	my $id     = $self->generate_alias( $alias->name() );
	my $post   = $self->post_address( $id );

	$self->add_to_alias( $alias, $post, @$users );
	$self->{Aliases}->save( $alias, $id );

	$self->reply({ To => $from, Subject => "Created list $id" },
		"Mailing list created.  Post to $post." );

	return $alias;
}

sub command_clone
{
	my $self       = shift;

	my $from       = $self->address_field( 'from' );
	(my $subject   = $self->{Message}->get( 'Subject' )) =~ s/^\*clone\*\s+//;
	my ($alias_id) = $self->parse_alias( $subject );
	my $parent     = $self->{Aliases}->fetch( $alias_id );
	my $alias      = $self->{Aliases}->create( $from );
	my $users      = $self->process_body( $alias, @{$self->{Message}->body()} );
	my $id         = $self->generate_alias( $alias_id );
	my $post       = $self->post_address( $id );

	$self->add_to_alias( $alias, $post, @{ $parent->members() }, @$users );

	$self->{Aliases}->save( $alias, $id );

	$self->reply({ To => $from, Subject => "Cloned alias $alias_id => $id" },
		"Mailing list created.  Post to $post." );

	return $alias;
}

sub address_field
{
	my ($self, $field) = @_;
	my @values = Mail::Address->parse( $self->{Message}->get( $field ) );
	return wantarray ? @values : $values[0]->format();
}

sub generate_alias
{
	my ($self, $id) = @_;

	$id      ||= sprintf '%x', reverse scalar time;

	while ($self->{Aliases}->exists( $id ))
	{
		$id    = sprintf '%x', ( reverse ( time() + rand($$) ));
	}

	return $id;
}

sub post_address
{
	my ($self, $id) = @_;
	my ($address)   = $self->address_field( 'to' );
	my $host        = $address->host();
	(my $base       = $address->user()) =~ s/\+([^+]+)$//;

	return "$base+$id\@$host";
}

sub process_body
{
	my ($self, $alias, @body) = @_;

	my $attributes  = $alias->attributes();
	while ( @body and $body[0] =~ /^(\w+): (.*)$/ )
	{
		my ($directive, $value) = (lc($1), $2);
		$alias->$directive( $value ) if exists $attributes->{ $directive };
		shift @body;
	}

	return \@body;
}

sub reply
{
	my ($self, $headers, @body) = @_;
	$headers->{'X-MSL-Seen'}    = '1';

	my $mailer = Mail::Mailer->new();
	$mailer->open( $headers );
	$mailer->print( @body );
	$mailer->close();
}

sub command_unsubscribe
{
	my $self         = shift;
	my ($alias, $id) = $self->fetch_alias();
	chomp( my $from  = $self->{Message}->get( 'from' ) );

	$self->reply({ To => $from, Subject => "Remove from $alias" },
		 ($alias->remove_address( $from ) and
		  $self->{Aliases}->save( $alias, $id )) ?
			"Unsubscribed $from successfully." :
			"Unsubscribe unsuccessful for $from.  Check the address."
	);
}

sub process
{
	my $self    = shift;

	return if $self->{Message}->get('X-MSL-Seen');
	my $command = $self->find_command();
	return $self->$command() if $command;

	my $alias   = $self->fetch_alias();
	return $self->deliver( $alias ) if $alias;
	$self->reject();
}

sub find_command
{
	my $self      = shift;
	my ($subject) = $self->{Message}->get('subject') =~ /^\*(\w+)\*/;

	my $command   = 'command_' . lc $subject;
	return $self->can( $command ) ? $command : '';
}

sub deliver
{
	my ($self, $alias) = @_;

	my $body    = $self->{Message}->body();
	my $name    = $alias->name();
	my $host    = ($self->address_field( 'To' ))[0]->host();
	my $message = $self->copy_headers();

	unless ($self->can_deliver( $alias, $message ))
	{
		my $body = delete $message->{Body};
		$self->reply( $message, $body );
		return;
	}

	my $desc    = $alias->description() || '';

	if ( $alias->auto_add() )
	{	
		$self->add_to_alias( $alias, $message->{To}, delete $message->{CC} );
		$self->{Aliases}->save( $alias, $name );
	}

	$message->{Bcc}        = $alias->members();
	$message->{'List-Id'}  = ( $desc ? qq|"$desc" | : '') .
		"<$name.list-id.$host>"; 
	$message->{'Reply-To'} = $message->{To};

	$self->reply( $message, @$body, "To unsubscribe:" .
		qq| reply to this sender alone with "*UNSUBSCRIBE*" in the subject.|
	);
}

sub copy_headers
{
	my $self    = shift;
	my $headers = $self->{Message}->head()->header_hashref();

	while (my ($key, $value) = each %$headers)
	{
		next unless ref $value eq 'ARRAY';
		chomp @$value;
		$headers->{$key} = join(', ', @$value);
	}

	delete $headers->{'From '};

	for my $header ( qw( from CC to subject ))
	{
		$headers->{ ucfirst($header) } = $self->{Message}->get( $header );
	}

	return $headers;
}


sub reject
{
	my $reason = $_[1] || "Invalid alias\n";
	$! = 100;
	die $reason;
}

sub notify
{
	my ($self, $alias, $id) = splice( @_, 0, 3 );

	my $owner = $alias->owner();
	my $desc  = $alias->description();

	for my $address ( @_ )
	{
		$self->reply({
			From       => $owner,
			To         => $address, 
			'Reply-To' => $id,
			Subject    => "Added to alias $id",
		}, "You have been subscribed to alias $id by $owner.\n\n", $desc );
	}
}

sub can_deliver
{
	my ($self, $alias, $message) = @_;
	if ( $alias->closed() and not
		grep { $_ eq $message->{From} } @{ $alias->members() })
	{
		$message->{To}      = $message->{From};
		$message->{Subject} = 'Alias closed';
		$message->{Body}    = 'This alias is closed to non-members.';
		return;
	}
	return 1 unless my $expires = $alias->expires();
	if ($expires < time())
	{
		$message->{To}      = $message->{From};
		$message->{Subject} = 'Alias expired';
		$message->{Body}    = 'This alias has expired.';
		return;
	}
	return 1;
}

sub add_to_alias
{
	my ($self, $alias, $id, @addresses) = @_;
	my @added = $alias->add( @addresses ) or return;
	$self->notify( $alias, $id, @added );
}

1;
__DATA__

=head1 NAME

Mail::SimpleList - module for managing simple, temporary, easy mailing lists

=head1 SYNOPSIS

	use Mail::SimpleList;
	my $list = Mail::SimpleList->new( 'alias' );
	$list->process();

=head1 DESCRIPTION

Sometimes, you just need a really simple mailing list to last for a few days.
You want it to be easy to create and easy to use, and you want it to be easy to
unsubscribe.  It's not worth setting up a complex system with one of the
existing mailing list managers, but it's nice not to worry about who does and
doesn't want to participate.

Mail::SimpleList, Mail::SimpleList::Aliases, and Mail::SimpleList::Alias make
it easy to create a temporary mailing list system.

=head1 USING LISTS

=head2 INSTALLING

Please see the README file in this distribution for installation and
configuration instructions.  You'll need to configure your mail server just a
little bit, but you only need to do it once.  The rest of these instructions
assume you've installed Mail::SimpleList to use the address
C<alias@example.com>.

=head2 CREATING A LIST

To create a list, send an e-mail to the address C<alias@example.com>.  In the
subject of the message, include the phrase C<*new*>.  In the body of the
message, include a list of e-mail addresses to be subscribed to the list.  For
example, you may create a list including Alice, Bob, and Charlie with an e-mail resembling:

	From:    you@example.com
	To:      alias@example.com
	Subject: *new*

	alice@example.com
	bob@example.com
	charlie@example.com

You will receive a response informing you that the list has been created.
Alice, Bob, and Charlie will each receive a response indicating that you have
subscribed them to the alias.  Each message will include the alias-specific
posting address.  In this case, it might be C<alias+3abfeec@example.com>.

You can specify additional directives when creating a list.  Please see
L<Directives> for more information.

=head2 POSTING TO A LIST

To post to a list, simply send an e-mail to the address provided in the
subscription or creation message.  It will be sent to everyone currently
subscribed to the list.  You do not need to use the Reply-All feature on your
mailer; Mail::SimpleList sets the C<Reply-To> header automatically.

If you do include other e-mail addresses in the C<CC> header, Mail::SimpleList
will, by default, automatically subscribe them to the list, informing them of
this action and sending them the current message.  No one should receive
duplicate messages, even if he is already subscribed.

=head2 UNSUBSCRIBING FROM A LIST

To unsubscribe from a list, send an e-mail to the address provided with a
subject line of C<*unsubscribe*>.  In Bob's case, this message might be:

	From:    bob@example.com
	To:      alias+3abfeec@example.com
	Subject: *unsubscribe*

	no body here; it doesn't matter

Bob will receive an e-mail confirming that he has been unsubscribed.  He will
not receive any more messages directed to this list unless he resubscribes.

=head2 CLONING A LIST

To clone a list, duplicating its subscribers but setting yourself as the owner
and changing other attributes, send a message to the main address (in this
case, C<alias@example.com>) with a subject containing the command C<*clone*>
and the address of the list to clone.  Alice could clone the list above by
sending the message:

	From:    alice@example.com
	To:      alias@example.com
	Subject: *clone* alias+3abfeec@example.com

	doug@example.com

Alice will receive a list creation message and the members of the cloned list
will each receive a message informing them that they have been added to the
clone.  Doug will also be added to this new list.

=head1 DIRECTIVES

Lists have six attributes.  Two, the list owner and the list members, are set
automatically when the list is created.  You can specify the other attributes
by including directives when you create or clone a list.

Directives go in the body of the creation or clone message, B<before> the list
of e-mail addresses to add.  They take the form:

	Directive: option

=head2 Closed

This directive governs whether or not the list is closed to non-subscribers.
If so, only members of the list may send a message to the list.  Everyone else
will receive an error message indicating that the list is closed.

This attribute is false by default; anyone can post to a list.  To enable it,
use either directive form:

	Closed: yes
	Closed: 1

=head2 Expires

This directive governs how long the list will be available.  After its
expiration date has passed, no one may send a message to the list.  Everyone
will then receive an error message indicating that the list has expired.

This attribute is not set by default; lists do not expire.  To enable it, use
the directive form:

	Expires: 7d2h

This directive will cause the list to expire in seven days and two hours.
Valid time units are:

=over 4

=item * C<m>, for minute.  This is sixty (60) seconds.

=item * C<h>, for hour.  This is sixty (60) minutes.

=item * C<d>, for day.  This is twenty-four (24) hours.

=item * C<w>, for week. This is seven (7) days.

=item * C<M>, for month.  This is thirty (30) days.

=back

This should suffice for most purposes.

=head2 Auto_add

This directive governs whether addresses found in the C<CC> header will be
added automatically to the list.  By default, it is enabled.  To disable it,
use either directive form:

	Auto_add: no
	Auto_add: 0

=head2 Description

This is a single line that describes the purpose of the list.  It is sent to
everyone when they are added to the list.  By default, it is blank.  To set a
description, use the form:

	Description: This list is for discussing fluoridation.

=head2 Name

This isn't a directive in the sense that it's an intrinsic part of a list.
It's just a way to give a list a nicer name when it's being created.  Instead
of having to rename a list to a nicer name, you can specify it with:

	Name: meat-eaters

Only letters, numbers, dashes, and the underscore characters are allowed in
names.

=head1 METHODS

=over 4

=item * new( $alias_directory, [ $filehandle ] )

C<new()> takes one mandatory argument and one optional argument.
C<$alias_directory> is the path to the directory where alias data is stored.
C<$filehandle> is a filehandle (or a reference to a glob) from which to read an
incoming message.  By default, it will read from C<STDIN>, as that is how mail
filters work.

=item * process()

Processes one incoming message.

=back

=head1 AUTHOR

chromatic, C<chromatic@wgz.org>, with suggestions from various friends and
family as well as the subset of the Portland Perl Mongers who do not appear in
a previous category.

=head1 BUGS

No known bugs, though something odd happens when you send a message with an
invalid command to the base address (in our example, C<alias@example.com>).

=head1 TODO

=over 4

=item * look for addable addresses in C<To> header as well

=item * allow the list owner to add people even if C<Auto_add> is off

=item * explore appropriate mailing-list and references headers

=item * explicitly forbid loops (strip out all other alias addresses when
sending)

=item * allow list creation to be restricted to a set of users

=item * show lists of which I am a member

=back

=head1 COPYRIGHT

Copyright (c) 2003, chromatic.  All rights reserved.  This module is
distributed under the same terms as Perl itself, in the hope that it is useful
but certainly under no guarantee.  Hey, it's free.
