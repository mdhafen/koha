package C4::MembersExternal;

# Copyright 2009 Michael Hafen
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA


use strict;
use warnings;
use vars qw( %MembersExternal_Context );
use Digest::MD5 qw(md5_base64);
use C4::Context;

our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,$debug);

BEGIN {
    $VERSION = 3.00;
    $debug = $ENV{DEBUG} || 0;
    require Exporter;
    @ISA = qw(Exporter);
    #Get data
    push @EXPORT, qw(
	&GetMemberDetails_External
	&ListMembers_External
	&GetExternalMapping
	&GetExternalMappedCategories
	&GetExternalMappingsForCategory
	&GetExternalNumCategoryMappings
	);

    #Modify Data
    push @EXPORT, qw(
	&ModExternalMapping
	);

    #Add Data
    push @EXPORT, qw(
	&AddExternalMapping
	);

    #Remove Data
    push @EXPORT, qw(
	&DelExternalMapping
	);

    # Private subs
    #Get data
    push @EXPORT_OK, qw(
	&GetExternalField
	&GetExternalAttrib
	&GetExternalAllAttribs
	);

    #Check data
    push @EXPORT_OK, qw(
	&PatronInMappedCategory
	);

    #Connection handling
    push @EXPORT_OK, qw(
	&DBI_BuildQuery
	);
}

%MembersExternal_Context = (
    conn => undef,  # DBI handle
    engine => C4::Context->config('MembersExternalEngine'),
    pass_method => C4::Context->config('MembersExternalPassMethod'),
    host => C4::Context->config('MembersExternalHost'),
    user => C4::Context->config('MembersExternalUser'),
    pass => C4::Context->config('MembersExternalPass'),
    schema => C4::Context->config('MembersExternalSchema'),
    );

=head1 NAME

C4::MembersExternal - Perl Module extending C4::Members to allow getting member
 information from sources other than the Koha database

=head1 SYNOPSIS

use C4::MembersExternal;

=head1 DESCRIPTION

This module contains routines for adding members/patrons/borrowers where the
 information for those members/patrons/borrowers is held in a source other than
 the Koha database

=head1 VARIABLES

There are a few configuration variable to handle.  First is the method, which
 is a dbi driver.  Second is how the passwords are stored, either 'plain' or
 'md5'.  Third the host, username, and password with access to the database.

=head1 FUNCTIONS

=over 2

=item GetMemberDetails_External

  $borrower = &GetMemberDetails_External($cardnumber);

Returns information on a patron (borrower) by card number.

C<$borrower> is a reference-to-hash with keys from the C<borrowers> table of
 the Koha database for columns that have been mapped to an external database or
 directory.

=cut

sub GetMemberDetails_External {
    my ( $cardnumber, $category ) = @_;
    my ( @columns, @filter, $query, $sth );
    my ( $data, $result );

    return $data unless ( $category = PatronInMappedCategory( undef, $cardnumber, $category ) );

    @columns = GetExternalAllAttribs( $category );
    my $filter_field = GetExternalAttrib( 'cardnumber', $category );
    push @filter, { 'field' => $filter_field, 'op' => '=', 'value' => $cardnumber };
    $query = DBI_BuildQuery( $category, \@columns, \@filter );
    return {} unless ( defined $query );
    $sth = $MembersExternal_Context{ conn }->prepare( $query ) or return {};
    $sth->execute;
    $data = $sth->fetchrow_hashref;

    foreach my $attrib ( keys %$data ) {
        my $field = GetExternalField( $attrib, $category );
        $$result{ $field } = $$data{ $attrib };
    }

    return $result;
}

=item ListMembers_External
  ( $Koha, $External ) = &ListMembers_External( $category, $branch );

Creates two lists: C<Koha> and C<External> which list all the users in the Koha
 database and the External database for a given patron C<category>.  This is
 used by the syncronize script to make sure the Koha database is in sync with
 the External database for a few key fields.

=cut

sub ListMembers_External {
    my ( $category, $branch ) = @_;
    my ( %koha, $external );

    my $dbh = C4::Context->dbh;
    my $query = "SELECT * FROM borrowers";
    $query .= " WHERE branchcode = ". $dbh->quote( $branch ) if ( $branch );
    my $sth = $dbh->prepare( $query );
    $sth->execute();
    while ( my $data = $sth->fetchrow_hashref ) {
        $$data{cardnumber} =~ s/^\s*//;
        $$data{cardnumber} =~ s/\s*$//;
        $koha{ $$data{cardnumber} } = $data;
    }

    my @filter;
    my $cardfield = GetExternalAttrib( 'cardnumber', $category );
    if ( $branch ) {
        my $branchfield = GetExternalAttrib( 'branchcode', $category );
        push @filter, { 'field' => $branchfield, 'op' => '=', 'value' => $branch };
    }

    $query = DBI_BuildQuery( $category, [ $cardfield ], \@filter );
    return ( \%koha, {} ) unless ( defined $query );
    $sth = $MembersExternal_Context{ conn }->prepare( $query );
    $sth->execute;
    while ( my ( $card ) = $sth->fetchrow ) {
        $card =~ s/^\s*//;
        $card =~ s/\s*$//;
        $$external{ $card } = 1;
    }

    return ( \%koha, $external );
}

=item PatronInMappedCategory
  $category = &PatronInMappedCategory( $borrowernumber, $cardnumber );

Checkes the C<borrowers_external_structure> table to see if there is a mapping
 set for the patrons patron category.  Uses either C<borrowernumber> or
 C<cardnumber>.  Returns the patrons C<category> or undef.

=cut

sub PatronInMappedCategory {
    my ( $borrnum, $cardnum, $cat ) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;
    my @inputs;
    my $result;

    my $query = "SELECT categorycode FROM borrowers WHERE ";
    if ( $cat ) {
        $result = $cat;
    } elsif ( $borrnum ) {
        $query .= "borrowernumber = ?";
        push @inputs, $borrnum;
    } elsif ( $cardnum ) {
        $query .= "cardnumber = ?";
        push @inputs, $cardnum;
    } else {
        warn "PatronInMappedCategory() couldn't find members categorycode without cardnumber or borrowernumber" if $debug;
        return undef;
    }

    unless ( $cat ) {
        $sth = $dbh->prepare( $query );
        $sth->execute( @inputs );
        ( $result ) = $sth->fetchrow;
    }

    my @mapped_cats_ar = GetExternalMappedCategories();
    my %mapped_cats = map { $_ => 1 } @mapped_cats_ar;

    $result = ( $mapped_cats{ $result } ) ? $result : undef;

    return $result;
}

=item &GetExternalField
  $column = &GetExternalField( $field, $category );

handles the convertion of a database attribute back to the Koha field.

=cut

sub GetExternalField {
    my ( $field, $category ) = @_;
    my $column;
    my $dbh = C4::Context->dbh;
    my $query = "SELECT kohafield FROM borrowers_external_structure WHERE attrib LIKE ?";
    $query .= " AND categorycode = ". $dbh->quote( $category ) if ( $category );
    my $sth = $dbh->prepare( $query );
    $sth->execute( "\%$field" );  # watch out for column aliases
    ( $column ) = $sth->fetchrow;
    return $column;
}

=item &GetExternalAttrib
  $column = &GetExternalAttrib( $field, $category );

handles the convertion of a Koha field to the database field

=cut

sub GetExternalAttrib {
    my ( $field, $category ) = @_;
    my $column;
    my $dbh = C4::Context->dbh;
    my $query = "SELECT attrib FROM borrowers_external_structure WHERE kohafield = ?";
    $query .= " AND categorycode = ". $dbh->quote( $category ) if ( $category );
    my $sth = $dbh->prepare( $query );
    $sth->execute( $field );
    ( $column ) = $sth->fetchrow;
    $sth->finish;

    return $column;
}

=item &GetExternalAllAttribs
  $columns = &GetExternalAllAttribs( $category );

Grabs all the Koha fields that are mapped for C<$category>.  Returns an array-ref.

=cut

sub GetExternalAllAttribs {
    my ( $category ) = @_;
    my %columns;
    my $dbh = C4::Context->dbh;
    my $query;

    #  get the specific mappings for this category
    $query = "SELECT kohafield,attrib FROM borrowers_external_structure WHERE categorycode = ?";
    my $sth = $dbh->prepare( $query );
    $sth->execute( $category );
    while ( $_ = $sth->fetchrow_arrayref ) {
        $columns{ $$_[0] } = $$_[1];
    }

    return values %columns;
}

=item &GetExternalMappedCategories

=cut

sub GetExternalMappedCategories {
    my ( @all_cats );

    my $dbh = C4::Context->dbh;
    my $query = "SELECT categorycode FROM borrowers_external_structure GROUP BY categorycode";
    my $sth = $dbh->prepare( $query );
    $sth->execute;
    unless ( $sth->rows == 0 ) {
        while ( my ( $cat ) = $sth->fetchrow ) {
            push @all_cats, $cat if ( $cat ne '' );
        }
    }
    $sth->finish;

    return @all_cats;
}

=item &GetExternalMappingsForCategory

Returns an array-ref of hash-refs containing column mappings for a patron category.
Basically just returns the database contents.

=cut

sub GetExternalMappingsForCategory {
    my ( $category ) = @_;
    my ( $mappings );

    my $dbh = C4::Context->dbh;
    my $query = "SELECT * FROM borrowers_external_structure WHERE categorycode = ?";
    my $sth = $dbh->prepare( $query );
    $sth->execute( $category );
    $mappings = $sth->fetchall_arrayref({});
    return $mappings;
}

=item &GetExternalNumCategoryMappings

Returns the categorycode and number of column mappings.  If a category is
supplied returns only the number of mappings for that category.

=cut

sub GetExternalNumCategoryMappings {
    my ( $category ) = @_;
    my ( %mappings );
    my @bind = ();

    my $dbh = C4::Context->dbh;
    my $query = "SELECT categorycode,COUNT(*) AS count FROM borrowers_external_structure ";
    if ( $category ) {
	$query .= "WHERE categorycode = ? ";
	push @bind, $category;
    }
    $query .= "GROUP BY categorycode";
    my $sth = $dbh->prepare( $query );
    $sth->execute( @bind );
    while ( my $row = $sth->fetchrow_hashref() ) {
	$mappings{ $$row{categorycode} } = $$row{count};
    }
    return \%mappings;
}

=item &GetExternalMapping

Accessor function to get the database row for a specific mapping.  Input is
either the externalid, or the category and koha field of the mapping.  Output is
a hash ref as returned from the database.

=cut

sub GetExternalMapping {
    my ( $externalid, $category, $field ) = @_;
    my $dbh = C4::Context->dbh;
    my ( $sql, @params ) = ( '', () );
    my $mapping;

    if ( $externalid ) {
	$sql = "SELECT * FROM borrowers_external_structure WHERE externalid = ?";
	push @params, $externalid;
    } elsif ( $category && $field ) {
	$sql = "SELECT * FROM borrowers_external_structure WHERE categorycode = ? AND kohafield = ?";
	push @params, ( $category, $field );
    }
    my $sth = $dbh->prepare( $sql );
    $sth->execute( @params );
    $mapping = $sth->fetchrow_hashref();

    return $mapping;
}

=item &ModExternalMapping

Accessor function to modify an existing mapping.  Input is a hash with keys from
the borrowers_external_structure table, and the values to update with

=cut

sub ModExternalMapping {
    my ( $mapping ) = @_;
    my $dbh = C4::Context->dbh;
    my $sql = "
      UPDATE borrowers_external_structure
         SET categorycode = ?, liblibrarian = ?,
             kohafield = ?, attrib = ?, filter = ?,
             dblink = ?
       WHERE externalid = ? ";
    my $sth = $dbh->prepare( $sql );
    $sth->execute(
	$mapping->{categorycode}, $mapping->{liblibrarian},
	$mapping->{kohafield}, $mapping->{attrib}, $mapping->{filter},
	$mapping->{dblink},
	$mapping->{externalid}
	);
}

=item &AddExternalMapping

Add a mapping for a patron field to a column in an external database.  Input is
a hash ref with the values to add.

=cut

sub AddExternalMapping {
    my ( $mapping ) = @_;
    my $dbh = C4::Context->dbh;
    my $sql = "
      INSERT INTO borrowers_external_structure
                  ( categorycode, liblibrarian,
                    kohafield, attrib, filter,
                    dblink )
           VALUES ( ?, ?, ?, ?, ?, ? )";
    my $sth = $dbh->prepare( $sql );
    $sth->execute(
	$mapping->{categorycode}, $mapping->{liblibrarian},
	$mapping->{kohafield}, $mapping->{attrib}, $mapping->{filter},
	$mapping->{dblink},
	);

    return $dbh->last_insert_id( '', '', 'borrowers_external_structure', 'externalid' );
}

=item &DelExternalMapping

Delete a single column mapping for a given patron category.  Input is the id of
the column to delete.
=cut

sub DelExternalMapping {
    my ( $externalid ) = @_;
    my $dbh = C4::Context->dbh;
    my $sql = "DELETE FROM borrowers_external_structure WHERE externalid = ?";
    my $sth = $dbh->prepare( $sql );
    $sth->execute( $externalid );
}

=item &DBI_BuildQuery

Makes sure there's a connection to the database and builds the query to get the requested information.

=cut

sub DBI_BuildQuery {
    my ( $category, $columns, $filters ) = @_;
    my ( $query, $query2 );
    my ( @l_columns, %tables, %weight, $first_table );

    unless ( $MembersExternal_Context{ conn } ) {
        # Connect to the external db
        # this DSN format is required for the sybase driver.
        # Also, Sybase when connecting to mssql doesn't like placeholders
        my $engine = $MembersExternal_Context{ engine };
        my $host = $MembersExternal_Context{ host };
        my $schema = $MembersExternal_Context{ schema };
        my $user = $MembersExternal_Context{ user };
        my $pass = $MembersExternal_Context{ pass };
        my $dsn = "DBI:$engine:server=$host;host=$host;database=$schema;sid=$schema";
        $MembersExternal_Context{ conn } = DBI->connect( $dsn, $user, $pass );
        unless ( defined $MembersExternal_Context{ conn } ) {
            warn "MembersExternal:  Couldn't connect to external DB!: ". $DBI::errstr if ( $debug );
            return undef;
        }
    }

    my $dbh = C4::Context->dbh;
    $query = "SELECT dblink, filter FROM borrowers_external_structure WHERE dblink LIKE ?";
    $query .= " AND categorycode = ". $dbh->quote( $category ) if ( $category );
    my $sth = $dbh->prepare( $query );

    $query2 = "SELECT dblink, filter FROM borrowers_external_structure WHERE dblink LIKE ? AND ( categorycode = '' OR categorycode IS NULL )";
    my $sth2 = $dbh->prepare( $query2 );

    # Clean up $columns
    #  Because the borrowers_external_structure fields must have table names,
    #  But the query results will not have them when using fetch_hashref
    #  So the parent sub probably cloned the fields without the table names
    #  to catch the value either way.
    foreach my $row ( @$columns ) {
        push @l_columns, $row if ( $row =~ /[^\.]+\.\S+/ );
    }

    # Figure out which tables we need now
    foreach my $row ( @$filters, @l_columns ) {
        my ( $table, $field );
        if ( ref( $row ) eq 'HASH' ) {
            $$row{ 'field' } =~ /([^\.\s]*)\.\S+/;
			$table = $1;
        } else {
            $row =~ /([^\.\s]*)\.\S+/;
			$table = $1;
        }
        $tables{ $table } = 1 if ( $table );
    }
    # And figure out how to join them
    if ( scalar keys %tables > 1 ) {
        foreach ( keys %tables ) {
            dbi_buildquerychain( $_, \%tables, \%weight, $filters, $sth, $sth2 );
        }
    } else {
        %weight = %tables;
		my ( $table ) = keys %tables;
        $sth->execute( "\%$table\%" );  # this table links to...
        while ( my ( $link, $filt ) = $sth->fetchrow ) {
            if ( $filt ) {
                $filt =~ /([\w\.]+)\s*(\W*)\s*(.*?)$/;
                push @$filters, { 'field' => $1, 'op' => $2, 'value' => $3 };
            }
        }
    }

    # put together the query using keys %weight and the dblinks from the db
    #  then add the $filters
    my $first = 1;
    $query = "SELECT ". join ',', @l_columns;
    $query .= " FROM ";

    my ( @tbls, @joins );
    foreach my $tbl ( sort { $weight{$b} <=> $weight{$a} } keys %weight ) {
        push @tbls, $tbl;
        push @joins, $tables{ $tbl };
    }
    shift @joins;  # don't need the first one.

    $query .= join ' CROSS JOIN ', @tbls;
    $query .= " WHERE " if ( @joins );
    $query .= join ' AND ', @joins;

    if ( @$filters ) {
        my @filter_array;
        foreach my $spec ( @$filters ) {
            my $value = ( $$spec{ 'value' } =~ /\D+/ ) ? $MembersExternal_Context{ conn }->quote( $$spec{ 'value' } ) : $$spec{ 'value' };
            push @filter_array, "$$spec{field} $$spec{op} $value";
        }
        unless ( $query =~ / WHERE / ) {
            $query .= " WHERE ";
        } else {
            $query .= " AND ";
        }
        $query .= join " AND ", @filter_array;
    }

    $query =~ s/WHERE $//;  # clean up trailing WHERE if there are no conditions

    warn $query if ( $debug );
    return $query;
}

# recursively called function to figure out how to join tables for a query

sub dbi_buildquerychain {
    my ( $table, $tables, $weight, $filters, $sth, $sth2 ) = @_;
    my ( $found, $link, %links, $filt );
    my ( $t1, $t2 );

    our $depth++;
    if ( $depth > 1000 ) {  # Just in case
        warn "I really hope you aren't actually trying to chain together more than 1000 tables" if ( $debug );
        die;
    }

    $sth->execute( "\%$table\%" );  # this table links to...
    if ( $sth->rows ) {  # categorycode set or default set?
        while ( ( $link, $filt ) = $sth->fetchrow ) {
            $links{ $link } = ( $filt ) ? $filt : "1";
        }
        $sth->finish;
    } else {
        $sth2->execute( "\%$table\%" );
        while ( ($link ) = $sth2->fetchrow ) {
            $links{ $link } = ( $filt ) ? $filt : "1";
        }
        $sth2->finish;
    }

    foreach $link ( keys %links ) {  # for all the links we have so far...
        $link =~ /([^\.\s]+)\.[\S]+.*?\=.*?([^\.\s]+)\.[\S]+/;
        ( $t1, $t2 ) = ( $1, $2 );
        $found = ( $t1 eq $table ) ? $t2 : $t1;  # the table this one links to

        $$weight{ $found } = 0 unless exists $$weight{ $found };  # init their
        $$weight{ $table } = 0 unless exists $$weight{ $table };  #  weight
        if ( exists $$tables{ $found } and $$tables { $found } ne "SEARCH" and $$weight{ $found } >= $$weight{ $table } ) {
            $$weight{ $table }++;  # we've seen $table and $found before
            $$weight{ $found } += $$weight{ $table } + 1;  # favor $found
            $$tables{ $table } = $link;
            if ( $links{ $link } ne "1" ) {
                $links{ $link } =~ /([\w\.]+)\s*(\W*)\s*(.*?)$/;
                push @$filters, { 'field' => $1, 'op' => $2, 'value' => $3 };
            }
        } elsif ( ! exists $$tables{ $found } ) {
            my $temp = $$tables{ $table };  # we haven't see $found before
            $$tables{ $table } = "SEARCH";  # search for it
            my $chain = dbi_buildquerychain( $found, $tables, $weight, $filters, $sth, $sth2 );
            if ( $temp ) {
                $$tables{ $table } = $temp;
            } else {
                delete $$tables{ $table };
            }
            if ( $chain ) {  # chain found and it's link recorded
                $$weight{ $table }++;
                $$weight{ $found } += $$weight{ $table } + 1;
                $$tables{ $table } = $link;
            }
        }
        delete $$weight{ $found } unless $$weight{ $found } > 0;
        delete $$weight{ $table } unless $$weight{ $table } > 0;
    }

    $depth--;
    return $$tables{ $table };
}

END { }    # module clean-up code here (global destructor)

1;

__END__

=back

=head1 AUTHOR

Michael Hafen for WCSD

=cut
