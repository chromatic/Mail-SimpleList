use Module::Build;

my $build = Module::Build->new(
	module_name => 'Mail::SimpleList',
	license     => 'perl',
	requires    =>
	{
		Class::Roles     => '0.30',
		Mail::Action     => '0.30',
		Mail::Internet   => '1.53',
		Pod::Simple      => '',
		YAML             => '0.35',
	},
	build_requires       =>
	{
		Test::Exception  => '',
		Test::MockObject => '0.11',
		Test::Simple     => '0.47',
	},
	dist_version_from => 'lib/Mail/SimpleList.pm',
	dist_author       => 'chromatic <chromatic@wgz.org>',
);

$build->create_build_script();
