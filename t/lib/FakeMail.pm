package FakeMail;

use strict;
use vars '$AUTOLOAD';

sub new
{
	bless {}, $_[0];
}

sub open
{
	my ($self, $headers)     = @_;
	@$self{ keys %$headers } = values %$headers;
}

sub print
{
	my $self = shift;
	$self->{body} = join('', @_ );
}

sub close {}

sub raw_message
{
	my $self    = shift;
	my $body    = delete $self->{body};
	my $message;

	while (my ($header, $value) = each %{ $self })
	{
		$message .= "$header: $value\n";
	}

	$message .= "\n" . $body;

	return $message;
}

sub AUTOLOAD
{
	my $self  = shift;
	$AUTOLOAD =~ s/.*:://;
	return if $AUTOLOAD eq 'DESTROY';
	return $self->{$AUTOLOAD} if exists $self->{$AUTOLOAD};
}

1;
