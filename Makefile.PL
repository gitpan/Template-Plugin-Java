use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> 'Template::Plugin::Java',
	VERSION_FROM	=> 'lib/Template/Plugin/Java.pm', # finds $VERSION
	ABSTRACT	=> 'Generate Java Classes from XML description files and templates.',
	EXE_FILES	=> [ qw( bin/tjava ) ],
	AUTHOR		=> 'Rafael Kitover (caelum@debian.org)',
	PREREQ_PM	=> {Template => 0, XML::Simple => 0},
	dist		=> {
		COMPRESS => 'gzip -9f',
		SUFFIX   => 'gz'
	}
);
