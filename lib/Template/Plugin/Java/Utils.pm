package Template::Plugin::Java::Utils;

@EXPORT_OK = qw(
	parseOptions sqlType2JavaType simplifyPath findPackageDir isNum
	castJavaString determinePackage createTemplate parseCmdLine
);

use strict;
use base qw(Exporter);
use Carp;
use Template::Plugin::Java::Constants qw/:all/;

# Creates a new Template with reasonable options.
sub createTemplate {
	use Template;
	use Template::Constants qw/:status/;
	my %options = ref $_[0] ? %{+shift} : @_
		if $_[0];
	
# Enable template compilation if version of Template is 2 or greater.
	if ($Template::VERSION !~ /^[01]/) {
		$options{COMPILE_EXT} = '.compiled';
	}

	my $template = new Template({
		INTERPOLATE	=> 1,
		EVAL_PERL	=> 1,
		PRE_CHOMP	=> 1,
		RECURSION	=> 1,
		INCLUDE_PATH	=> $ENV{TEMPLATEPATH},
		CATCH		=> {'default' => sub {
			my ($context, $type, $info) = @_;
			print STDERR "Error generating class "
				. $context->stash->get("class")
				. ":\n\t$type: $info\n\n\n";
			return STATUS_STOP;
		}},
		%options
	});

	return $template;
}


# Replaces c_c with cC and nosomething=whatever with something=0 in the keys of
# a hash.
sub parseOptions {
	my %options = ();

	if (@_ > 1) {
		%options = @_;
	} elsif (UNIVERSAL::isa($_[0], 'HASH')) {
		%options = %{+shift};
	}

	for my $option (keys %options) {
		if ($option =~ /^no(.*)/) {
			delete $options{$option};
			$option = $1;
			$options{$option} = 0;
		}
		if (($_ = $option) =~ s/_(\w)/\U$1/g) {
			$options{$_} = delete $options{$option};
		}
	}

	return wantarray ? %options : \%options;
}

# Adds to or sets an option in a hash, supports nested arrays and boolean
# options. The logic here is one of those things that just works the way it is
# and seems decipherable, but don't mess with it.
sub setOption (\%$;$) {
	my ($options, $option, $value) = @_;

	if (not exists $options->{$option}) {
		$options->{$option} = $value || TRUE;
	} elsif (not ref $options->{$option}) {
		if ($options->{$option} ne TRUE && $value) {
			$options->{$option} = [ $options->{$option}, $value ];
		} elsif (not $value) {
			return;
		} else {
			$options->{$option} = $value;
		}
	} elsif (not $value) {
		return;
	} elsif (ref $options->{$option} eq 'ARRAY') {
		push @{$options->{$option}}, $value;
	} elsif (ref $options->{$option} eq 'HASH') {
		$options->{$option}{$value} = TRUE;
	} elsif (UNIVERSAL::can($options->{$option}, $value)) {
		$options->{$option}->$value();
	}
}

# Parses @ARGV into a hash of options and values, leaving everything else that
# is most likely a list of files on @ARGV.
sub parseCmdLine () {
	my (%options, @files);

	my ($value, $last_option, $last_option_had_value);

	while (defined ($_ = shift @ARGV)) {
		last if /^--$/;

		if (/^[-+]+(.*)=?(.*)/) {
			$last_option		= $1;
			$value			= $2;
			setOption %options, $last_option, $value;
			$last_option_had_value	= $2 ? TRUE : FALSE;
		} elsif ((not $last_option_had_value) && $last_option) {
			setOption %options, $last_option, $_;
			$last_option_had_value	= TRUE;
		} else {
			push @files, $_;
		}
	}

	push @ARGV, @files;
	return \%options;
}

sub sqlType2JavaType ($;$) {
	($_, my $precision) = @_;

	/^.*char$/i	&& return 'String';
	/^integer$/i	&& return 'int';
	/^bigint$/i	&& return 'long';
	/^smallint$/i	&& return 'short';

	/^numeric$/i	&& do {
		$precision <= 5	&& return 'short';
		$precision <= 10&& return 'int';
				   return 'long';
	};

	/^date$/i	&& return 'Date';
	/^.*binary$/i	&& return 'byte[]';

	croak "Cannot map SQL type $_ to Java type.";
}

# Remove any dir/../ or /./ or extraneous / from a path, as well as prepending
# the current directory if necessary.
sub simplifyPath ($) {
	use URI::file;
	my $path = shift;

	return URI::file->new_abs($path)->file;
}

# Find package in $ENV{CLASSPATH}.
sub findPackageDir ($) {
	my $package	= shift;
	my $classpath	= $ENV{CLASSPATH};
	my @classpath	= split /:/, $classpath;
	my @package	= split /\./, $package;
	my $package_dir	= join ("/", @package) . "/";

# Find the first match in CLASSPATH.
	for (map { "$_/$package_dir" } @classpath) {
		return $_ if -d;
	}

	return "";
}

# Determine the package of the current or passed-in directory.
sub determinePackage (;$) {
	my $dir = shift || ".";
	my @cwd = split m|/|, substr ( simplifyPath $dir, 1 );

	my $i = @cwd;
	while ($i--) {
		my $package = join ('.', @cwd[$i..$#cwd]);

		if (findPackageDir $package) {
			return $package;
		}
	}

	return join ('.', @cwd);	# If all else fails.
}

# Determines whether a string is a number or not.
sub isNum ($) {
	local $^W = undef if $^W;
	$_	  = shift;

	if (not defined $_) {
		return FALSE;
	} elsif ($_ != 0 or /^0*(?:\.0*)$/) {
		return TRUE;
	} else {
		return FALSE;
	}
}

# Casts a java String to another type using the appropriate code.
# Parameters: name of variable to cast, type to cast to.
sub castJavaString {
	my ($name, $type) = @_;

	for ($type) {
		/String/&& do { return $name };
		/int/	&& do { return "Integer.parseInt($name)" };
		/@{[SCALAR]}/ && do {
			my $type = $1;
			if ($type =~ /^[A-Z]/) {
				return "new $type($name)";
			} else {
				return "\u$type.parse\u$type($name)";
			}
		};
		die "Cannot cast $name from String to $type.";
	}
}

1;
