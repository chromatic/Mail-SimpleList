package FakeIn;

use Symbol 'gensym';

sub new
{
	my $class  = shift;
	my $symbol = gensym();
	tie *$symbol, $class, @_;
	return $symbol;
}

sub TIEHANDLE
{
	my ($class, @lines) = @_;
	bless \@lines, $class;
}

sub READLINE
{
	my $self = shift;
	return unless @$self;
	return shift @$self unless wantarray;
	my @lines = @$self;
	@$self    = ();
	return @lines;
}

sub FILENO
{
	1;
}

1;
