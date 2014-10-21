package Template::Plugin::JavaSQL;

=head1 NAME

Template::Plugin::JavaSQL - Help generate Java from database schemas.

=head1 SYNOPSES

Within an XML file processed by the Java plugin:

	<sql:
		query="select foo as f, bar as b from some_table"
	>

	or

	<sql:
		table="some_table"
	>

Via a template such as:

	[% USE Java %]
	[% Use JavaSQL %]
	...
	mySelect	= myConnection.prepareStatement(
	"select [% JavaSQL.columnNames.join(", ") %] from [% JavaSQL.tables.join(", ") %]
	[%- IF JavaSQL.where -%]
	 where [% JavaSQL.where %] 
	[% END %]
	[%- IF JavaSQL.order -%]
	order by [% JavaSQL.order %]
	[% END %]"
	);

=head1 DESCRIPTION

In addition to methods that refer to parts of a SQL query, any columns
resultant from the query or table will be added as java variables to the
variables hash, with close-as-possible mapped types.

=head1 METHODS

=over 8

=cut

use strict;
use base qw(Template::Plugin);
use Carp;
use DBI;
use Template::Plugin::Java::Utils qw/parseOptions sqlType2JavaType/;

use constant QUERY => qr/
	from
	\s*(.*)\s*	# $1 = tables
	(?:where
	 	\s*(.*)\s*	# $2 = condition
		(?:order\s*by
		\s*(.*)\s*$	# $3 = order by clause
		|
		\s*$)
	|
	\s*$)
/xi;

my $dbh = DBI->connect (
	$ENV{DBI_DSN},
	$ENV{DBI_USER},
	$ENV{DBI_PASS},
	{RaiseError => 1}
);

=item B<new>

Constructor. If given one parameter of type Template::Context, will use that as
a context. Then process the contents of "sql:" within the stash. This is what
typically happens inside a template when a [% USE JavaSQL %] directive is
encountered.

=cut
sub new {
	my $class = shift;
	my $self  = bless {}, ref $class || $class;

	if (UNIVERSAL::isa($_[0], 'Template::Context')) {
		$self->{context} = shift;
	} elsif (UNIVERSAL::isa($_[0], 'HASH')) {
		my $args = shift;
		@$self{ keys %$args } = values %$args;
	}

	if (@_ % 2 == 0) {
		my %more = @_;
		@$self{ keys %more } = values %more;
	}

# Now process the sql context if any.
	my $vars = $self->{context}->stash->get('variables');
	my $spec = delete $vars->{'sql:'};

	return unless $spec;

	my $query;
	if (exists $spec->{query}) {
		$query = $spec->{query};
	} elsif (exists $spec->{table}) {
		$query = "select * from ".$spec->{table};
	}

	my $sth = $dbh->prepare_cached($query);
	$sth->execute;

	my $columns = $sth->{NAME_lc};

	my $result;
	@$result{ @$columns } =
		map { { 'java:type' => sqlType2JavaType $_ } }
			map { $dbh->type_info($_)->{TYPE_NAME} }
				@{ $sth->{TYPE} };
	
	$self->{sth}     = $sth;
	$self->{columns} = [sort @$columns];
	$self->parseQuery($query);

	$result = parseOptions($result);

	@{$self->{column2var}}{ sort @$columns } = sort keys %$result;

# Place the variable info from the table back into main variables hash.
	@$vars{ keys %$result } = values %$result;

	return $self;
}

=item B<query>

The complete query, either supplied at instantiation or inferred from other
arguments.

=cut
sub query   { $_[0]->{query}   }

=item B<where>

The "where" portion of the SQL query, excluding the word "where" itself.

=cut
sub where   { $_[0]->{where}   }

=item B<tables>

A list of tables used by the query.

=cut
sub tables  { $_[0]->{tables}  }

=item B<tableCount>

Number of tables used by query.

=cut
sub tableCount { scalar @{$_[0]->{tables}} }

=item B<order>

An ORDER BY clause, if one was used.

=cut
sub order   { $_[0]->{order}   }

=item B<columnNames>

A list of column names used in the query.

=cut
sub columnNames { $_[0]->{columns} }

=item B<columnCount>

Number of columns returned from query.

=cut
sub columnCount { scalar @{$_[0]->{columns}} }

=item B<columns>

Intended to be used as [% FOREACH JavaSQL.columns %] ...
See L</SYNOPSYS>.

=cut
sub columns {
	my $self    = shift;
	my $vars    = $self->{context}->stash->get('variables');

	my $position= 1;

	return [ map {
		my $key  = $_;
		my $var  = $self->{column2var}{$key};
		my $type = $vars->{$var}{'java:type'};

		{
			name	=> $key,
			varName => $var,
			capName	=> ucfirst $var,
			type	=> $type,
			capType	=> ucfirst $type,
			value   => $vars->{$var},
			initializer =>
				Template::Plugin::Java->initializer($type),
			position=> $position++
		}
	} @{ $self->{columns} } ];
}

=item B<parseQuery>

Used internally to parse a SQL query and set the appropriate state variables.

=cut
sub parseQuery {
	my ($self, $query) = @_;

	$query =~ /@{[QUERY]}/;

	$self->{query}  = $query;
	$self->{tables} = [ split /\s*,\s*/, $1 ];
	$self->{where}  = $2;
	$self->{order}  = $3;
}

1;

__END__

=back

=head1 ENVIRONMENT

=over 8

=item B<DBI_DSN>

DBI Data Source Name, for example, the data source for MySQL and database name
"test" it would be: dbi:mysql:database=test

=item B<DBI_USER>

User name to connect to the database as.

=item B<DBI_PASS>

Password for database, can be blank for no password.

=back

=head1 AUTHOR

Rafael Kitover (caelum@debian.org)
The concept and related templates are based on Andrew Lanthier's dbgen
framework (an unreleased development utility).

=head1 COPYRIGHT

This program is Copyright (c) 2000 by Rafael Kitover. This program is free
software; you can redistribute it and/or modify it under the same terms as Perl
itself.

=head1 BUGS

Probably many.

=head1 TODO

A very great deal.

=head1 SEE ALSO

L<perl(1)>,
L<Template(3)>,
L<Template::Plugin::Java::Utils(3)>,
L<Template::Plugin::Java::Constants(3)>,

=cut
