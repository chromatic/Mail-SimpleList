package FakeIn;

sub new
{
	my $class = shift;
	local *GLOB;
	tie *GLOB, $class, @_;
	return \*GLOB;
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
