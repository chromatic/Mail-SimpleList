#!/usr/bin/perl -w

BEGIN
{
	chdir 't' if -d 't';
	unshift @INC, '../lib', '../blib/lib', 'lib';
}

use strict;

use FakeIn;
use FakeMail;
use File::Path 'rmtree';

use Test::More tests => 47;
use Test::MockObject;

mkdir 'alias';

END
{
	rmtree 'alias' unless @ARGV;
}

my @mails;
Test::MockObject->fake_module( 'Mail::Mailer', new => sub {
	push @mails, FakeMail->new();
	$mails[-1];
});

diag( 'Create a new alias and subscribe another user' );

my $fake_glob = FakeIn->new( split(/\n/, <<'END_HERE') );
From: me@home
To: alias@there
Subject: *new*

you@elsewhere
END_HERE

use_ok( 'Mail::SimpleList' ) or exit;

my $ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

my $mail = shift @mails;
is( $mail->To(),   'you@elsewhere',    '*new* list should notify added users' );
is( $mail->From(), 'me@home',          '... from the list creator' );
like( $mail->Subject(),
	qr/Added to alias/,                '... with a good subject' );
my $replyto = 'Reply-To';
ok( $mail->$replyto(),                 '... replying to the alias' );

like( $mail->body(),
	qr/You have been subscribed .+ by me\@home/,
	                                   '... with a subscription message' );

$mail = shift @mails;
is( $mail->To(), 'me@home',       '*new* in subject should respond to sender' );
like( $mail->Subject(),
	qr/^Created list/,            '... with success subject' ); 

like( $mail->body(),
	qr/^Mailing list created.  Post to /,
	                              '... and body' );

ok( $mail->body() =~ /Post to (alias\+(.+)\@.+)\./,
	                              '... containing alias id' );

my ($alias_add, $alias_id) = ($1, $2);
ok( $ml->{Aliases}->exists( $alias_id ), '... creating alias file' );

my $alias = $ml->{Aliases}->fetch( $alias_id );
ok( $alias, 'alias should be fetchable' );
is_deeply( $alias->members(), [ 'me@home', 'you@elsewhere' ],
	'... adding the correct members' );
is( $alias->owner(), 'me@home', '... and the owner' );

diag( "Send a message to the alias '$alias_add'" );

$fake_glob = FakeIn->new( split(/\n/, <<END_HERE) );
From: me\@home
To: $alias_add
Subject: Hi there

hi there
you guys
END_HERE

$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

$mail = shift @mails;
is_deeply( $mail->Bcc(), [ 'me@home', 'you@elsewhere' ],
	'sending a message to an alias should Bcc everyone' );
is( $mail->From(), "me\@home\n",         '... keeping from address' );
is( $mail->$replyto(), "$alias_add\n",   '... setting replies to the alias');
is( $mail->Subject(), "Hi there\n",      '... saving the subject' );
ok( ! $mail->Cc(),                       '... removing all Cc addresses' );
ok( ! $mail->To(),                       '... removing all To addresses' );

like( $mail->body(), qr/hi there/,       '... sending the message body' );
like( $mail->body(), qr/you guys/,       '... multiple lines' );
like( $mail->body(), qr/To unsubscribe/, '... appending unsubscribe message');

diag( "Remove an address from the alias" );

$fake_glob = FakeIn->new( split(/\n/, <<END_HERE) );
From: you\@elsewhere
To: $alias_add
Subject: *UNSUBSCRIBE*

END_HERE

$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

$alias = $ml->{Aliases}->fetch( $alias_id );
is_deeply( $alias->members(), [ 'me@home' ],
	'unsubscribing should remove an address from the alias' );

$mail = shift @mails;
is( $mail->To(), "you\@elsewhere",        '... responding to user' );
like( $mail->Subject(), qr/Remove from /, '... with remove subject' );

is( $mail->body(),'Unsubscribed you@elsewhere successfully.',
	                                      '... and a success message' );

diag( "Set an expiration date" );

$fake_glob = FakeIn->new( split(/\n/, <<'END_HERE') );
From: me@home
To: alias@there
Subject: *new*

Expires: 7d

you@elsewhere
he@his.place
she@hers
END_HERE

$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

# should be the reply
$mail = pop @mails;
my $regex = qr/Post to (alias\+(.+)\@.+)\./;
like( $mail->body(), $regex,
	                   'new aliases with expiration date should be creatable' );

($alias_add, $alias_id) = $mail->body() =~ $regex;
$alias = $ml->{Aliases}->fetch( $alias_id );

ok( $alias->expires(), '... setting expiration on the alias to true' );

is_deeply( $alias->members(),
	[ 'me@home', 'you@elsewhere', 'he@his.place', 'she@hers' ],
	                   '... and collecting mail addresses properly' );

$alias->{expires} = time() - 100;
$ml->{Aliases}->save( $alias, $alias_id );

$fake_glob = FakeIn->new( split(/\n/, <<END_HERE) );
From: me\@home
To: $alias_add
Subject:  probably too late

this message will not reach you in time
END_HERE

@mails = ();

$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

$mail = shift @mails;
is( $mail->To(), "me\@home\n",                '... responding to user' );
like( $mail->Subject(), qr/expired/,          '... with expired in subject' );

is( $mail->body(), 'This alias has expired.', '... and an expiration message' );

diag( 'Create a closed alias' );

$fake_glob = FakeIn->new( split(/\n/, <<'END_HERE') );
From: me@home
To: alias@there
Subject: *new*

Closed: yes

you@there
END_HERE

$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

# should be the reply
$mail  = pop @mails;
$regex = qr/Post to (alias\+(.+)\@.+)\./;
like( $mail->body(), $regex, 'new closed alias should be creatable' );

($alias_add, $alias_id) = $mail->body() =~ $regex;
$alias = $ml->{Aliases}->fetch( $alias_id );
ok( $alias->closed(), '... and should be marked as closed' );

$fake_glob = FakeIn->new( split(/\n/, <<END_HERE) );
From: not\@list
To: $alias_add
Subject: hi there

You shouldn't receive this.
END_HERE

@mails = ();
$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

$mail = shift @mails;
is( $mail->To(), "not\@list\n",             '... responding to user' );
like( $mail->Subject(), qr/closed/,         '... with closed in subject' );

is( $mail->body(),
	'This alias is closed to non-members.', '... and a closed list message' );

diag( 'Create a non-adding alias' );

$fake_glob = FakeIn->new( split(/\n/, <<'END_HERE') );
From: me@home
To: alias@there
Subject: *new*

Auto_add: no

END_HERE

$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

# should be the reply
$mail  = shift @mails;
$regex = qr/Post to (alias\+(.+)\@.+)\./;
like( $mail->body(), $regex, 'new no auto-add alias should be creatable' );
($alias_add) = $mail->body() =~ /$regex/;

$fake_glob = FakeIn->new( split(/\n/, <<END_HERE) );
From: me\@home
To: $alias_add
Cc: you\@there
Subject: hello

Hello, here is a message for you.
END_HERE

@mails = ();
$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

($alias_add, $alias_id) = $mail->body() =~ /$regex/;
$alias                  = $ml->{Aliases}->fetch( $alias_id );

is_deeply( $alias->members(), [ 'me@home' ],
	                       'posting to alias should not add copied addresses' );

$mail = shift @mails;
is( $mail->Cc(), "you\@there\n",
                           '... but should keep them on the list' );
is_deeply( $mail->Bcc(),
	[ 'me@home' ],         '... along with alias subscribers' );

$fake_glob = FakeIn->new( split(/\n/, <<END_HERE) );
From: me\@home
To: alias\@there
Subject: *clone* $alias_add

Auto_add: 1
END_HERE

@mails = ();
$ml = Mail::SimpleList->new( 'alias', $fake_glob );
$ml->process();

my $old_id         = $alias_id;
$mail = shift @mails;
(undef, $alias_id) = $mail->body() =~ /$regex/
	or diag "Alias not cloned; tests will fail\n";

my $oldalias = $alias;
$alias       = $ml->{Aliases}->fetch( $alias_id );

is_deeply( $alias->members(), $oldalias->members(),
	                                'cloning a list should clone its members' );
ok( $alias->auto_add(),             '... processing directives' );
is( $mail->To(),     'me@home',     '... responding to cloner' );
is( $alias->owner(), 'me@home',     '... setting owner to cloner' );
like( $mail->Subject(),
	qr/Cloned alias $old_id/,       '... marking clone in subject' );
