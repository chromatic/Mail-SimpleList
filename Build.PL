use Module::Build;

my $build = Module::Build->new(
	module_name => 'Mail::SimpleList',
	license     => 'perl',
	requires    => {
		Class::Roles     => '0.30',
		Mail::Action     => '0.20',
		Mail::Address    => '1.53',
		Mail::Internet   => '1.53',
		Pod::Simple      => '',
		Test::Exception  => '',
		Test::MockObject => '0.11',
		Test::Simple     => '0.47',
		YAML             => '0.35',
	},
	dist_version_from => 'lib/Mail/SimpleList.pm',
);

$build->create_build_script;
